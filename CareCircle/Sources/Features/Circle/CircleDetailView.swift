import SwiftData
import SwiftUI

// MARK: - CircleDetailView

struct CircleDetailView: View {
    let circle: Circle
    let signedInAppleUserID: String

    @State private var isEditingRecipient = false

    private var activeMemberCount: Int {
        circle.members.count(where: { $0.status != .removed })
    }

    private var invitedMemberCount: Int {
        circle.members.count(where: { $0.status == .invited })
    }

    var body: some View {
        List {
            Section {
                CircleHero(circleName: circle.name, recipient: circle.careRecipient)
                    .listRowInsets(.init(
                        top: Theme.tightSpacing,
                        leading: Theme.spacing,
                        bottom: Theme.tightSpacing,
                        trailing: Theme.spacing
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            recipientSection
            membersSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.ccBackground)
        .navigationTitle(circle.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .sheet(isPresented: $isEditingRecipient) {
            if let recipient = circle.careRecipient {
                EditCareRecipientView(recipient: recipient)
            }
        }
    }

    @ViewBuilder
    private var recipientSection: some View {
        if let recipient = circle.careRecipient {
            Section("Care Recipient") {
                LabeledContent("Name", value: recipient.fullName)
                    .foregroundStyle(Color.ccText)

                if let dob = recipient.dateOfBirth {
                    LabeledContent("Date of birth", value: dob.formatted(date: .long, time: .omitted))
                        .foregroundStyle(Color.ccText)
                }

                if !recipient.primaryConditions.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.tightSpacing) {
                        Text("Primary conditions")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.ccSecondary)
                        Text(recipient.primaryConditions.joined(separator: ", "))
                            .foregroundStyle(Color.ccText)
                    }
                    .padding(.vertical, Theme.tightSpacing / 2)
                }

                Button {
                    isEditingRecipient = true
                } label: {
                    Label("Edit Care Recipient", systemImage: "pencil")
                }
                .foregroundStyle(Color.ccPrimary)
            }
        }
    }

    private var membersSection: some View {
        Section("Members") {
            NavigationLink {
                MembersListView(circle: circle, signedInAppleUserID: signedInAppleUserID)
            } label: {
                HStack(spacing: Theme.spacing) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Color.ccPrimary)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Members")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.ccText)
                        Text(membersSummary)
                            .font(.footnote)
                            .foregroundStyle(Color.ccSecondary)
                    }
                }
            }
        }
    }

    private var membersSummary: String {
        if invitedMemberCount > 0 {
            return "\(activeMemberCount) active · \(invitedMemberCount) invited"
        }
        if activeMemberCount == 1 {
            return "1 active member"
        }
        return "\(activeMemberCount) active members"
    }
}
