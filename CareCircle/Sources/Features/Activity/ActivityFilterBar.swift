import SwiftUI

// MARK: - ActivityFeedFilter

struct ActivityFeedFilter: Equatable, Sendable {
    var type: ActivityType?
    var authorAppleUserID: String?

    var isActive: Bool {
        type != nil || authorAppleUserID != nil
    }
}

// MARK: - ActivityFilterAuthor

struct ActivityFilterAuthor: Identifiable, Hashable, Sendable {
    let appleUserID: String
    let displayName: String
    var id: String {
        appleUserID
    }
}

// MARK: - ActivityFilterBar

struct ActivityFilterBar: View {
    @Binding var filter: ActivityFeedFilter
    let availableTypes: [ActivityType]
    let availableAuthors: [ActivityFilterAuthor]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.tightSpacing) {
                    typeChip(label: "All types", isOn: filter.type == nil) {
                        filter.type = nil
                    }
                    ForEach(availableTypes, id: \.self) { type in
                        typeChip(label: type.displayName, isOn: filter.type == type) {
                            filter.type = type
                        }
                    }
                }
                .padding(.horizontal, Theme.spacing)
            }

            if !availableAuthors.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.tightSpacing) {
                        typeChip(label: "Everyone", isOn: filter.authorAppleUserID == nil) {
                            filter.authorAppleUserID = nil
                        }
                        ForEach(availableAuthors) { author in
                            typeChip(
                                label: author.displayName,
                                isOn: filter.authorAppleUserID == author.appleUserID
                            ) {
                                filter.authorAppleUserID = author.appleUserID
                            }
                        }
                    }
                    .padding(.horizontal, Theme.spacing)
                }
            }
        }
        .padding(.vertical, Theme.tightSpacing)
        .background(Color.ccBackground)
    }

    private func typeChip(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Theme.spacing)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(
                    Capsule().fill(isOn ? Color.ccPrimary : Color.ccSurface)
                )
                .foregroundStyle(isOn ? Color.white : Color.ccText)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
