import OSLog
import SwiftData
import SwiftUI

// MARK: - MembersListView

struct MembersListView: View {
    let circle: Circle
    let signedInAppleUserID: String

    @Environment(BackendRealtimeClient.self) private var realtimeClient
    @Environment(\.modelContext) private var modelContext
    @State private var isAddingMember = false
    @State private var memberPendingRemoval: Member?

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
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if canRemove(member) {
                                    Button(role: .destructive) {
                                        memberPendingRemoval = member
                                    } label: {
                                        Label("Remove", systemImage: "person.fill.xmark")
                                    }
                                }
                            }
                    }
                } header: {
                    sectionHeader(for: group.status, count: group.members.count)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable {
            await realtimeClient.snapshotResync(
                circleIds: [circle.id],
                modelContext: modelContext
            )
        }
        .background(Color.ccBackground)
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .toolbar { toolbar }
        .sheet(isPresented: $isAddingMember) {
            AddMemberView(circle: circle, ownerAppleUserID: signedInAppleUserID)
        }
        .confirmationDialog(
            "Remove from Circle?",
            isPresented: removalDialogBinding,
            titleVisibility: .visible,
            presenting: memberPendingRemoval
        ) { member in
            Button("Remove \(member.displayName)", role: .destructive) {
                remove(member)
                memberPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                memberPendingRemoval = nil
            }
        } message: { member in
            Text(
                "\(member.displayName) will be taken off the member list and their seat freed. Information already synced to their device isn't recalled."
            )
        }
    }

    private var removalDialogBinding: Binding<Bool> {
        Binding(
            get: { memberPendingRemoval != nil },
            set: { isPresented in
                if !isPresented { memberPendingRemoval = nil }
            }
        )
    }

    /// Owner-only. The circle owner can never be removed, and an already-removed
    /// row offers no further action.
    private func canRemove(_ member: Member) -> Bool {
        guard permissions.canRemoveMembers, member.status != .removed else { return false }
        let isCircleOwner = member.role == .owner
            || (!member.appleUserID.isEmpty && member.appleUserID == circle.ownerAppleUserID)
        return !isCircleOwner
    }

    /// Marks the member removed locally; the change syncs to other members via
    /// CloudKit and frees a roster seat. CloudKit data already replicated to the
    /// removed member's device is not recalled by this action — hard revocation
    /// is tracked separately as a device-verified follow-up.
    private func remove(_ member: Member) {
        member.status = .removed
        do {
            try modelContext.save()
        } catch {
            let description = String(describing: error)
            AppLogger.persistence.error("Failed to remove member: \(description, privacy: .public)")
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
                .disabled(!hasInviteCapacity)
                .accessibilityHint(inviteHint)
                .featureGate(.sharedCircle, circle: circle, viewerAppleUserID: signedInAppleUserID)
            }
        }
    }

    private var hasInviteCapacity: Bool {
        activeCount < circle.subscriptionTier.seatCap
    }

    private var inviteHint: String {
        if !circle.entitles(.sharedCircle) {
            return "Upgrade to invite caregivers."
        }
        if !hasInviteCapacity {
            return "Your \(circle.subscriptionTier.displayName) plan is full. Upgrade for more seats."
        }
        return "Send a Circle invitation."
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
