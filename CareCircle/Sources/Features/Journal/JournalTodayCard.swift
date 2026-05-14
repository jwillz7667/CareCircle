import SwiftData
import SwiftUI

// MARK: - JournalTodayCard

/// Compact "did anyone log today's check-in yet?" card for the Home
/// feed. Two states:
///
/// 1. Nothing logged for today → a 5-emoji mood preview row that
///    doubles as a quick-log shortcut. Tapping any emoji jumps into
///    the composer with that mood pre-selected.
/// 2. Already logged today → a one-line summary (mood + symptoms) with
///    edit affordance.
struct JournalTodayCard: View {
    let circle: Circle
    let author: ActivityAuthorContext

    @Environment(\.modelContext) private var modelContext
    @State private var composerTarget: ComposerTarget?

    private enum ComposerTarget: Identifiable {
        case create(initialMood: Mood)
        case edit(JournalEntry)

        var id: String {
            switch self {
            case let .create(mood): "create-\(mood.rawValue)"
            case let .edit(entry): "edit-\(entry.id.uuidString)"
            }
        }
    }

    private var todayEntry: JournalEntry? {
        let today = Calendar.current.startOfDay(for: .now)
        return circle.journalEntries.first {
            Calendar.current.isDate($0.recordedAt, inSameDayAs: today)
        }
    }

    private var recipientFirstName: String {
        let raw = circle.careRecipient?.fullName ?? ""
        return raw.split(separator: " ").first.map(String.init) ?? "today"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(Color.ccPrimary)
                Text("How is \(recipientFirstName) today?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Spacer()
                if todayEntry != nil {
                    Button("Edit") {
                        if let existing = todayEntry { composerTarget = .edit(existing) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ccPrimary)
                }
            }

            if let entry = todayEntry {
                loggedSummary(entry)
            } else {
                moodSelector
            }
        }
        .padding(14)
        .background(Color.ccSurface, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, Theme.spacing)
        .sheet(item: $composerTarget) { target in
            NavigationStack {
                switch target {
                case let .create(mood):
                    JournalEntryComposerView(
                        circle: circle,
                        author: author,
                        existing: nil,
                        initialMood: mood
                    )
                case let .edit(entry):
                    JournalEntryComposerView(circle: circle, author: author, existing: entry)
                }
            }
        }
    }

    private var moodSelector: some View {
        HStack(spacing: 8) {
            ForEach(Mood.allCases) { mood in
                Button {
                    composerTarget = .create(initialMood: mood)
                } label: {
                    VStack(spacing: 2) {
                        Text(mood.emoji)
                            .font(.system(size: 24))
                        Text(mood.label)
                            .font(.caption2)
                            .foregroundStyle(Color.ccSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.ccBackground, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log \(mood.label.lowercased())")
            }
        }
    }

    private func loggedSummary(_ entry: JournalEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.mood.emoji)
                .font(.system(size: 32))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.mood.label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                if entry.symptoms.isEmpty {
                    Text("No symptoms reported.")
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                } else {
                    Text(entry.symptoms.prefix(4).map(\.displayName).joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                        .lineLimit(2)
                }
                if !entry.authorDisplayName.isEmpty {
                    Text("Logged by \(entry.authorDisplayName)")
                        .font(.caption2)
                        .foregroundStyle(Color.ccSecondary)
                }
            }
            Spacer()
        }
    }
}
