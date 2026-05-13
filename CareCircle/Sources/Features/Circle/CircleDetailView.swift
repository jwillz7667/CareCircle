import SwiftData
import SwiftUI

// MARK: - CircleDetailView

struct CircleDetailView: View {
    let circle: Circle

    @State private var isEditingRecipient = false

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
        Section("Members (\(circle.members.count))") {
            ForEach(circle.members.sorted(by: { $0.joinedAt < $1.joinedAt })) { member in
                memberRow(member)
            }
        }
    }

    private func memberRow(_ member: Member) -> some View {
        HStack(spacing: Theme.spacing) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.ccPrimary)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.ccText)
                Text(member.role.displayName)
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            }
        }
    }
}
