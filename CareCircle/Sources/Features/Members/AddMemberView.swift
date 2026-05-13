import OSLog
import SwiftData
import SwiftUI

// MARK: - AddMemberView

struct AddMemberView: View {
    let circle: Circle
    let ownerAppleUserID: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.circleSharingService) private var sharingService
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var role: MemberRole = .familyMember
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var pendingSharePayload: CircleSharePayload?

    private static let assignableRoles: [MemberRole] = [
        .familyMember,
        .paidFamily,
        .paidAide,
        .viewOnly,
    ]

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeMemberCount: Int {
        circle.members.count(where: { $0.status != .removed })
    }

    private var capReached: Bool {
        activeMemberCount >= CircleSharingService.memberCap
    }

    private var canSubmit: Bool {
        !isSubmitting && !trimmedDisplayName.isEmpty && !capReached
    }

    var body: some View {
        NavigationStack {
            Form {
                if capReached {
                    Section {
                        Label(
                            "This Circle is full (\(CircleSharingService.memberCap) members).",
                            systemImage: "person.3.fill"
                        )
                        .foregroundStyle(Color.ccDanger)
                    }
                }

                Section {
                    LabeledContent("Name") {
                        TextField("e.g., Daniel", text: $displayName)
                            .textContentType(.name)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.next)
                            .accessibilityLabel("Member display name")
                            .disabled(isSubmitting || capReached)
                    }

                    Picker("Role", selection: $role) {
                        ForEach(Self.assignableRoles, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    .disabled(isSubmitting || capReached)
                } header: {
                    Text("New member")
                } footer: {
                    Text("They'll see this name and role inside the Circle. You can change either later.")
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
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
            .navigationTitle("Invite member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isSubmitting)
            .sheet(item: shareSheetItem) { wrapped in
                ActivityShareSheet(items: [wrapped.payload.url, wrapped.payload.shareTitle]) {
                    pendingSharePayload = nil
                    dismiss()
                }
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
                Task { await submit() }
            }
            .disabled(!canSubmit)
        }
    }

    private var shareSheetItem: Binding<CircleSharePayloadIdentified?> {
        Binding(
            get: {
                if let payload = pendingSharePayload {
                    return CircleSharePayloadIdentified(payload: payload)
                }
                return nil
            },
            set: { newValue in
                if newValue == nil {
                    pendingSharePayload = nil
                }
            }
        )
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let payload = try await sharingService.share(circle, suggestedRole: role)
            let invited = Member(
                appleUserID: "",
                displayName: trimmedDisplayName,
                role: role,
                status: .invited,
                invitedAt: .now,
                invitedByAppleUserID: ownerAppleUserID,
                inviteShareURLString: payload.url.absoluteString
            )
            invited.circle = circle
            modelContext.insert(invited)
            do {
                try modelContext.save()
            } catch {
                modelContext.delete(invited)
                AppLogger.persistence.error(
                    "Failed to persist invited Member: \(String(describing: error), privacy: .public)"
                )
                errorMessage = "Couldn't save the invitation locally. Please try again."
                return
            }
            pendingSharePayload = payload
        } catch {
            errorMessage = error.errorDescription ?? "Couldn't create the invitation."
            AppLogger.cloudKit.error(
                "share failed in AddMemberView: \(error.errorDescription ?? "nil", privacy: .public)"
            )
        }
    }
}

// MARK: - CircleSharePayloadIdentified

/// `CircleSharePayload` isn't `Identifiable`, so the share-sheet binding wraps it.
private struct CircleSharePayloadIdentified: Identifiable {
    let payload: CircleSharePayload
    var id: String {
        payload.url.absoluteString
    }
}
