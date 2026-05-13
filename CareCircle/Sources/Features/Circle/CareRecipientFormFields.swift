import OSLog
import PhotosUI
import SwiftUI

// MARK: - CareRecipientFormFields

struct CareRecipientFormFields: View {
    @Binding var draft: CareRecipientDraft

    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        Group {
            photoSection
            namesSection
            conditionsSection
            validationSection
        }
        .task(id: selectedPhoto) {
            await loadSelectedPhoto()
        }
    }

    // MARK: Sections

    private var photoSection: some View {
        Section {
            HStack(spacing: Theme.spacing) {
                PhotoCircleView(
                    imageData: draft.photoData,
                    diameter: 88,
                    isEditable: true,
                    selection: $selectedPhoto
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Photo")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.ccText)
                    Text("Tap to choose from your library.")
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Theme.tightSpacing / 2)
        }
    }

    private var namesSection: some View {
        Section {
            LabeledContent("First name") {
                TextField("Required", text: $draft.firstName)
                    .textContentType(.givenName)
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.next)
                    .accessibilityLabel("First name")
            }

            LabeledContent("Last name") {
                TextField("Optional", text: $draft.lastName)
                    .textContentType(.familyName)
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.next)
                    .accessibilityLabel("Last name")
            }

            Toggle("Add date of birth", isOn: dobToggleBinding)
                .tint(Color.ccPrimary)

            if draft.dateOfBirth != nil {
                DatePicker(
                    "Date of birth",
                    selection: dobBinding,
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .tint(Color.ccPrimary)
            }
        }
    }

    private var conditionsSection: some View {
        Section {
            TextField(
                "e.g., type 2 diabetes, hypertension",
                text: $draft.primaryConditionsInput,
                axis: .vertical
            )
            .lineLimit(2 ... 4)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .accessibilityLabel("Primary conditions")
            .accessibilityHint("Separate multiple conditions with commas.")
        } header: {
            Text("Primary conditions")
        } footer: {
            Text("Separate multiple conditions with commas. You can edit these later.")
                .font(.footnote)
                .foregroundStyle(Color.ccSecondary)
        }
    }

    @ViewBuilder
    private var validationSection: some View {
        if let error = draft.validationError, error != .firstNameRequired {
            Section {
                Label(error.errorDescription ?? "Validation error", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.ccDanger)
            }
        }
    }

    // MARK: Bindings

    private var dobToggleBinding: Binding<Bool> {
        Binding(
            get: { draft.dateOfBirth != nil },
            set: { newValue in
                if newValue, draft.dateOfBirth == nil {
                    draft.dateOfBirth = Calendar.current.date(byAdding: .year, value: -75, to: .now)
                } else if !newValue {
                    draft.dateOfBirth = nil
                }
            }
        )
    }

    private var dobBinding: Binding<Date> {
        Binding(
            get: { draft.dateOfBirth ?? .now },
            set: { draft.dateOfBirth = $0 }
        )
    }

    // MARK: Photo loading

    private func loadSelectedPhoto() async {
        guard let item = selectedPhoto else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                draft.photoData = data
            }
        } catch {
            AppLogger.app.error("Photo load failed: \(String(describing: error), privacy: .public)")
        }
    }
}
