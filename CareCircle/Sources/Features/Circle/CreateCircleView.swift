import OSLog
import SwiftData
import SwiftUI

// MARK: - CreateCircleView

struct CreateCircleView: View {
    let authState: AuthState

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var circleName = ""
    @State private var draft = CareRecipientDraft()
    @State private var isSaving = false
    @State private var saveError: String?

    private var trimmedCircleName: String {
        circleName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !isSaving && !trimmedCircleName.isEmpty && draft.isValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name") {
                        TextField("e.g., Mom's Care", text: $circleName)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.next)
                            .accessibilityLabel("Circle name")
                    }
                } header: {
                    Text("Circle")
                } footer: {
                    Text("Members will see this name in their app.")
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                }

                CareRecipientFormFields(draft: $draft)

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(Color.ccDanger)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ccBackground)
            .navigationTitle("New Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(isSaving)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                save()
            }
            .disabled(!canSave)
            .accessibilityHint("Saves the new Circle and Care Recipient.")
        }
    }

    private func save() {
        guard case let .signedIn(user) = authState.status else {
            saveError = "You must be signed in to create a Circle."
            return
        }
        isSaving = true
        defer { isSaving = false }

        let recipient = draft.makeCareRecipient()
        let owner = Member(appleUserID: user.id, displayName: user.displayName, role: .owner)
        let newCircle = Circle(
            name: trimmedCircleName,
            ownerAppleUserID: user.id,
            careRecipient: recipient,
            members: [owner]
        )

        modelContext.insert(newCircle)
        modelContext.insert(recipient)
        modelContext.insert(owner)

        do {
            try modelContext.save()
            AppLogger.persistence
                .info("Circle created (id prefix=\(newCircle.id.uuidString.prefix(8), privacy: .public)).")
            dismiss()
        } catch {
            saveError = error.localizedDescription
            AppLogger.persistence
                .error("Failed to save new Circle: \(String(describing: error), privacy: .public)")
        }
    }
}
