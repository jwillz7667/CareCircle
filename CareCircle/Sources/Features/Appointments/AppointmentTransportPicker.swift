import SwiftUI

// MARK: - AppointmentTransportPicker

/// Picker section binding the "who's driving" responsibility to an active
/// circle member (or no one). Caller passes the active member list and
/// receives the selected Apple user ID + display name back via bindings so
/// the parent draft has both fields for offline display.
struct AppointmentTransportPicker: View {
    let members: [Member]
    @Binding var selectedAppleUserID: String?
    @Binding var selectedDisplayName: String?

    private static let noneTag = "__none__"

    private var selectionTag: String {
        selectedAppleUserID ?? Self.noneTag
    }

    var body: some View {
        Section {
            Picker("Driving", selection: Binding(
                get: { selectionTag },
                set: applySelection
            )) {
                Text("No one assigned").tag(Self.noneTag)
                ForEach(members) { member in
                    Text(member.displayName).tag(member.appleUserID)
                }
            }
        } header: {
            Text("Transportation")
        } footer: {
            if members.isEmpty {
                Text("Invite circle members to assign transportation help.")
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            }
        }
    }

    private func applySelection(_ tag: String) {
        if tag == Self.noneTag {
            selectedAppleUserID = nil
            selectedDisplayName = nil
            return
        }
        if let match = members.first(where: { $0.appleUserID == tag }) {
            selectedAppleUserID = match.appleUserID
            selectedDisplayName = match.displayName
        }
    }
}
