import OSLog
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

// MARK: - ActivityComposerView

struct ActivityComposerView: View {
    let circle: Circle
    let author: ActivityAuthorContext

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var noteBody = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isProcessingPhoto = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var trimmedBody: String {
        noteBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasContent: Bool {
        !trimmedBody.isEmpty || photoData != nil
    }

    private var canSubmit: Bool {
        !isSubmitting && !isProcessingPhoto && hasContent && author.hasIdentity
    }

    private var resolvedType: ActivityType {
        photoData != nil ? .photo : .textNote
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "What happened?",
                        text: $noteBody,
                        axis: .vertical
                    )
                    .lineLimit(4 ... 10)
                    .accessibilityLabel("Note body")
                    .disabled(isSubmitting)
                } header: {
                    Text("Note")
                } footer: {
                    Text("Share an update with everyone in this Circle.")
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                }

                Section {
                    photoPickerRow

                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

                        Button(role: .destructive) {
                            self.photoData = nil
                            pickerItem = nil
                        } label: {
                            Label("Remove photo", systemImage: "trash")
                        }
                        .foregroundStyle(Color.ccDanger)
                        .disabled(isSubmitting)
                    }
                } header: {
                    Text("Photo (optional)")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(Color.ccDanger)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ccBackground)
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isSubmitting)
            .onChange(of: pickerItem) { _, newValue in
                Task { await loadPhoto(from: newValue) }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .disabled(isSubmitting)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Send") {
                submit()
            }
            .disabled(!canSubmit)
        }
    }

    private var photoPickerRow: some View {
        PhotosPicker(
            selection: $pickerItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            if isProcessingPhoto {
                Label("Loading photo…", systemImage: "photo.on.rectangle")
                    .foregroundStyle(Color.ccSecondary)
            } else if photoData == nil {
                Label("Choose a photo", systemImage: "photo.on.rectangle")
                    .foregroundStyle(Color.ccPrimary)
            } else {
                Label("Replace photo", systemImage: "photo.on.rectangle.angled")
                    .foregroundStyle(Color.ccPrimary)
            }
        }
        .disabled(isSubmitting)
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        errorMessage = nil
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }

        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Couldn't read that photo. Try another."
                return
            }
            guard let compressed = ActivityComposerImagePipeline.encode(raw) else {
                errorMessage = "That image format isn't supported."
                return
            }
            photoData = compressed
        } catch {
            AppLogger.persistence.error(
                "Photo load failed: \(String(describing: error), privacy: .public)"
            )
            errorMessage = "Couldn't load that photo."
        }
    }

    private func submit() {
        guard canSubmit else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let activity = Activity(
            authorAppleUserID: author.appleUserID,
            authorDisplayName: author.displayName,
            type: resolvedType,
            body: trimmedBody,
            photoData: photoData
        )
        activity.circle = circle
        modelContext.insert(activity)

        do {
            try modelContext.save()
            scheduleExtraction(for: activity)
            dismiss()
        } catch {
            modelContext.delete(activity)
            AppLogger.persistence.error(
                "Failed to save Activity: \(String(describing: error), privacy: .public)"
            )
            errorMessage = "Couldn't save the post. Please try again."
        }
    }

    private func scheduleExtraction(for activity: Activity) {
        guard !trimmedBody.isEmpty else { return }
        let redactor = PHIRedactor(
            circle: circle,
            currentCaregiverDisplayName: author.displayName
        )
        let extractor = EntityExtractorFactory.makeDefault(redactor: redactor)
        ActivityExtractionService.enqueue(
            activityID: activity.id,
            text: trimmedBody,
            extractor: extractor,
            in: modelContext
        )
    }
}
