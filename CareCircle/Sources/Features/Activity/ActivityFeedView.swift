import SwiftData
import SwiftUI

// MARK: - ActivityFeedView

struct ActivityFeedView: View {
    let circle: Circle
    let author: ActivityAuthorContext

    @State private var isComposingText = false
    @State private var isComposingVoice = false
    @State private var filter = ActivityFeedFilter()

    private var permissions: CirclePermissions {
        CirclePermissions.resolve(circle: circle, appleUserID: author.appleUserID)
    }

    private var sortedActivities: [Activity] {
        circle.activities.sorted(by: { $0.createdAt > $1.createdAt })
    }

    private var filteredActivities: [Activity] {
        sortedActivities.filter { activity in
            if let type = filter.type, activity.type != type {
                return false
            }
            if let authorID = filter.authorAppleUserID,
               activity.authorAppleUserID != authorID
            {
                return false
            }
            return true
        }
    }

    private var availableTypes: [ActivityType] {
        let present = Set(sortedActivities.map(\.type))
        let order: [ActivityType] = [
            .textNote, .photo, .voiceNote, .medTaken, .visit, .appointment, .alert, .system,
        ]
        return order.filter(present.contains)
    }

    private var availableAuthors: [ActivityFilterAuthor] {
        let pairs = sortedActivities.map { ($0.authorAppleUserID, $0.authorDisplayName) }
        var seen = Set<String>()
        var result: [ActivityFilterAuthor] = []
        for (id, name) in pairs where !id.isEmpty && !seen.contains(id) {
            seen.insert(id)
            result.append(ActivityFilterAuthor(appleUserID: id, displayName: name))
        }
        return result
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            scrollContent

            if permissions.canPostActivity {
                postButton
                    .padding(.trailing, Theme.spacing)
                    .padding(.bottom, Theme.spacing)
            }
        }
        .background(Color.ccBackground)
        .sheet(isPresented: $isComposingText) {
            ActivityComposerView(circle: circle, author: author)
        }
        .sheet(isPresented: $isComposingVoice) {
            VoiceComposerView(circle: circle, author: author)
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                CircleHero(circleName: circle.name, recipient: circle.careRecipient)
                    .padding(.horizontal, Theme.spacing)

                if !sortedActivities.isEmpty {
                    ActivityFilterBar(
                        filter: $filter,
                        availableTypes: availableTypes,
                        availableAuthors: availableAuthors
                    )
                }

                feedBody
                    .padding(.horizontal, Theme.spacing)
            }
            .padding(.top, Theme.spacing)
            .padding(.bottom, 96)
        }
    }

    @ViewBuilder
    private var feedBody: some View {
        if sortedActivities.isEmpty {
            emptyState
                .padding(.top, Theme.looseSpacing)
        } else if filteredActivities.isEmpty {
            VStack(spacing: Theme.tightSpacing) {
                Text("No posts match this filter.")
                    .font(.body)
                    .foregroundStyle(Color.ccSecondary)
                Button("Clear filters") {
                    filter = ActivityFeedFilter()
                }
                .buttonStyle(.bordered)
                .tint(Color.ccPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.looseSpacing)
        } else {
            LazyVStack(spacing: Theme.spacing) {
                ForEach(filteredActivities) { activity in
                    NavigationLink {
                        ActivityDetailView(
                            activity: activity,
                            author: author,
                            permissions: permissions
                        )
                    } label: {
                        ActivityRowView(activity: activity, author: author)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacing) {
            Image(systemName: "text.bubble")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.ccPrimary)
            Text("No posts yet.")
                .font(.headline)
                .foregroundStyle(Color.ccText)
            Text(permissions.canPostActivity
                ? "Tap the Post button to share an update."
                : "Posts from Circle members will appear here.")
                .font(.subheadline)
                .foregroundStyle(Color.ccSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.looseSpacing)
        }
        .padding(.vertical, Theme.looseSpacing)
    }

    private var postButton: some View {
        Menu {
            Button {
                isComposingText = true
            } label: {
                Label("Text or photo", systemImage: "square.and.pencil")
            }
            Button {
                isComposingVoice = true
            } label: {
                Label("Voice note", systemImage: "mic.fill")
            }
        } label: {
            Label("Post", systemImage: "plus")
                .font(.body.weight(.semibold))
                .padding(.horizontal, Theme.spacing)
                .padding(.vertical, 12)
                .foregroundStyle(Color.white)
                .background(
                    Capsule().fill(Color.ccPrimary)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 4)
        }
        .accessibilityHint("Open the new post composer.")
    }
}
