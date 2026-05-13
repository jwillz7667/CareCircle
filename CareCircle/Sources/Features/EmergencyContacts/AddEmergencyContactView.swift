import SwiftData
import SwiftUI

// MARK: - AddEmergencyContactView

struct AddEmergencyContactView: View {
    let circle: Circle

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var relationship = ""
    @State private var isPrimary = false
    @State private var isMedical = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField("Relationship (optional)", text: $relationship)
                }

                Section {
                    Toggle("Primary contact", isOn: $isPrimary)
                    Toggle("Medical contact", isOn: $isMedical)
                } footer: {
                    Text("Primary contacts are called first when SOS is triggered.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
            !phone.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let normalizedPhone = phone
            .trimmingCharacters(in: .whitespaces)
            .filter { $0.isNumber || $0 == "+" }
        guard normalizedPhone.count >= 4 else {
            errorMessage = "Enter a valid phone number."
            return
        }

        if isPrimary {
            for existing in circle.emergencyContacts where existing.isPrimary {
                existing.isPrimary = false
                existing.updatedAt = .now
            }
        }

        let trimmedRelationship = relationship.trimmingCharacters(in: .whitespaces)
        let contact = EmergencyContact(
            name: name.trimmingCharacters(in: .whitespaces),
            relationship: trimmedRelationship.isEmpty ? nil : trimmedRelationship,
            phoneE164: normalizedPhone,
            isPrimary: isPrimary,
            isMedical: isMedical,
            sortOrder: isPrimary ? 0 : 100
        )
        contact.circle = circle

        modelContext.insert(contact)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Couldn't save contact: \(error.localizedDescription)"
        }
    }
}
