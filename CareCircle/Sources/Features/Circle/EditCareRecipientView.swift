import OSLog
import SwiftData
import SwiftUI

// MARK: - EditCareRecipientView

struct EditCareRecipientView: View {
    let recipient: CareRecipient

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CareRecipientDraft
    @State private var isSaving = false
    @State private var saveError: String?

    init(recipient: CareRecipient) {
        self.recipient = recipient
        _draft = State(initialValue: .from(recipient))
    }

    private var canSave: Bool {
        !isSaving && draft.isValid
    }

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle("Edit Care Recipient")
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
        }
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }

        draft.apply(to: recipient)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
            AppLogger.persistence
                .error("Failed to save Care Recipient edits: \(String(describing: error), privacy: .public)")
        }
    }
}
