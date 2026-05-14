import SwiftData
import SwiftUI

// MARK: - JournalListView

/// Caregiver-facing log of how the Care Recipient is doing day-to-day —
/// mood (1–5), the symptoms anyone observed, and a free-text note.
/// Sorted most-recent first. Tapping a row opens the composer in edit
/// mode; a "Log today" pill at the top short-circuits straight into a
/// fresh entry when nothing has been recorded for today yet.
struct JournalListView: View {
    let circle: Circle
    let author: ActivityAuthorContext

    @Environment(\.modelContext) private var modelContext
    @State private var composerTarget: ComposerTarget?

    private enum ComposerTarget: Identifiable {
        case create
        case edit(JournalEntry)

        var id: String {
            switch self {
            case .create: "create"
            case let .edit(entry): entry.id.uuidString
            }
        }
    }

    private var entries: [JournalEntry] {
        circle.journalEntries.sorted { $0.recordedAt > $1.recordedAt }
    }

    private var todayEntry: JournalEntry? {
        let today = Calendar.current.startOfDay(for: .now)
        return circle.journalEntries.first { Calendar.current.isDate($0.recordedAt, inSameDayAs: today) }
    }

    var body: some View {
        List {
            Section { todayRow }

            if entries.isEmpty {
                Section { emptyContent }
            } else {
                Section("History") {
                    ForEach(entries) { entry in
                        Button {
                            composerTarget = .edit(entry)
                        } label: {
                            entryRow(entry)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(entries[index])
                        }
                        try? modelContext.save()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ccBackground)
        .navigationTitle("Symptom journal")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .sheet(item: $composerTarget) { target in
            NavigationStack {
                switch target {
                case .create:
                    JournalEntryComposerView(circle: circle, author: author, existing: nil)
                case let .edit(entry):
                    JournalEntryComposerView(circle: circle, author: author, existing: entry)
                }
            }
        }
    }

    @ViewBuilder
    private var todayRow: some View {
        if let todayEntry {
            Button {
                composerTarget = .edit(todayEntry)
            } label: {
                todayLoggedRow(todayEntry)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                composerTarget = .create
            } label: {
                logTodayPill
            }
            .buttonStyle(.plain)
        }
    }

    private var logTodayPill: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.title3)
                .foregroundStyle(Color.ccPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Log today's check-in")
                    .font(.headline)
                    .foregroundStyle(Color.ccText)
                Text("Mood + symptoms + a short note. Visible to everyone in the Circle.")
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.ccSecondary)
        }
        .padding(.vertical, 4)
    }

    private func todayLoggedRow(_ entry: JournalEntry) -> some View {
        HStack(spacing: 12) {
            Text(entry.mood.emoji)
                .font(.system(size: 30))
            VStack(alignment: .leading, spacing: 2) {
                Text("Today — \(entry.mood.label)")
                    .font(.headline)
                    .foregroundStyle(Color.ccText)
                if !entry.symptoms.isEmpty {
                    Text(entry.symptoms.prefix(3).map(\.displayName).joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                } else {
                    Text("No symptoms reported.")
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                }
            }
            Spacer()
            Image(systemName: "pencil")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.ccSecondary)
        }
        .padding(.vertical, 4)
    }

    private func entryRow(_ entry: JournalEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .center, spacing: 2) {
                Text(entry.mood.emoji).font(.system(size: 24))
                Text(entry.recordedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.ccSecondary)
            }
            .frame(width: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.mood.label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                if !entry.symptoms.isEmpty {
                    Text(entry.symptoms.map(\.displayName).joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                        .lineLimit(2)
                }
                if !entry.notes.isEmpty {
                    Text(entry.notes)
                        .font(.footnote)
                        .foregroundStyle(Color.ccText)
                        .lineLimit(2)
                }
                if !entry.authorDisplayName.isEmpty {
                    Text("Logged by \(entry.authorDisplayName)")
                        .font(.caption2)
                        .foregroundStyle(Color.ccSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.ccPrimary.opacity(0.7))
            Text("No entries yet.")
                .font(.headline)
                .foregroundStyle(Color.ccText)
            Text("Log a daily mood and symptoms to spot trends over time.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ccSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
