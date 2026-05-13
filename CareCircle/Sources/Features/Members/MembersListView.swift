import SwiftData
import SwiftUI

// MARK: - MembersListView

struct MembersListView: View {
    let circle: Circle
    let signedInAppleUserID: String

    @State private var isAddingMember = false

    private var permissions: CirclePermissions {
        CirclePermissions.resolve(circle: circle, appleUserID: signedInAppleUserID)
    }

    private var grouped: [(status: MemberStatus, members: [Member])] {
        let byStatus = Dictionary(grouping: circle.members) { $0.status }
        let order: [MemberStatus] = [.active, .invited, .removed]
        return order.compactMap { status in
            let members = (byStatus[status] ?? []).sorted(by: { $0.joinedAt < $1.joinedAt })
            return members.isEmpty ? nil : (status, members)
        }
    }

    private var activeCount: Int {
        circle.members.count(where: { $0.status != .removed })
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.status) { group in
                Section {
                    ForEach(group.members) { member in
                        memberRow(member)
                    }
                } header: {
                    sectionHeader(for: group.status, count: group.members.count)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ccBackground)
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .toolbar { toolbar }
        .sheet(isPresented: $isAddingMember) {
            AddMemberView(circle: circle, ownerAppleUserID: signedInAppleUserID)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if permissions.canInviteMembers {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingMember = true
                } label: {
                    Label("Invite", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(activeCount >= CircleSharingService.memberCap)
                .accessibilityHint("Send a Circle invitation.")
            }
        }
    }

    private func sectionHeader(for status: MemberStatus, count: Int) -> some View {
        SectionHeader(title: "\(status.displayName) (\(count))")
    }

    private func memberRow(_ member: Member) -> some View {
        HStack(spacing: Theme.spacing) {
            Image(systemName: member.status == .invited ? "envelope.fill" : "person.crop.circle.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(member.status == .removed ? Color.ccSecondary : Color.ccPrimary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayLabel(for: member))
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.ccText)

                HStack(spacing: 6) {
                    MemberRoleBadge(role: member.role)
                    MemberStatusBadge(status: member.status)
                }

                if let detail = secondaryLine(for: member) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func displayLabel(for member: Member) -> String {
        if member.appleUserID == signedInAppleUserID, !member.appleUserID.isEmpty {
            return "\(member.displayName) (You)"
        }
        return member.displayName
    }

    private func secondaryLine(for member: Member) -> String? {
        switch member.status {
        case .active:
            return "Joined " + member.joinedAt.formatted(date: .abbreviated, time: .omitted)
        case .invited:
            let when = member.invitedAt ?? member.joinedAt
            return "Invited " + when.formatted(date: .abbreviated, time: .omitted)
        case .removed:
            return "Removed"
        }
    }
}
