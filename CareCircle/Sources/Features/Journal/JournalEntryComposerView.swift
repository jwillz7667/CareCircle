import OSLog
import SwiftData
import SwiftUI

// MARK: - JournalEntryComposerView

/// Form for creating or editing a `JournalEntry`. The composer enforces
/// the "one entry per calendar day per Circle" rule by either reusing
/// the existing entry for that day (passed in via `existing`) or
/// upserting via `recordedAt.startOfDay` on save.
struct JournalEntryComposerView: View {
    let circle: Circle
    let author: ActivityAuthorContext
    let existing: JournalEntry?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var recordedAt: Date = .now
    @State private var mood: Mood = .neutral
    @State private var selectedSymptoms: Set<SymptomTag> = []
    @State private var notes: String = ""
    @State private var saveError: String?

    init(
        circle: Circle,
        author: ActivityAuthorContext,
        existing: JournalEntry? = nil,
        initialMood: Mood? = nil
    ) {
        self.circle = circle
        self.author = author
        self.existing = existing
        _recordedAt = State(initialValue: existing?.recordedAt ?? .now)
        _mood = State(initialValue: existing?.mood ?? initialMood ?? .neutral)
        _selectedSymptoms = State(initialValue: Set(existing?.symptoms ?? []))
        _notes = State(initialValue: existing?.notes ?? "")
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $recordedAt, displayedComponents: .date)
            }

            Section("How is the Care Recipient today?") {
                moodPicker
            }

            Section("Symptoms") {
                symptomGrid
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 120)
            }

            if let saveError {
                Section {
                    Text(saveError)
                        .font(.footnote)
                        .foregroundStyle(Color.ccDanger)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ccBackground)
        .navigationTitle(existing == nil ? "New check-in" : "Edit check-in")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
            }
            if existing != nil {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        deleteExisting()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var moodPicker: some View {
        HStack(spacing: 12) {
            ForEach(Mood.allCases) { option in
                Button {
                    mood = option
                } label: {
                    VStack(spacing: 4) {
                        Text(option.emoji)
                            .font(.system(size: 30))
                        Text(option.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(mood == option ? Color.ccPrimary : Color.ccSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        mood == option
                            ? Color.ccPrimary.opacity(0.14)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(mood == option ? [.isSelected] : [])
            }
        }
    }

    private var symptomGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
            spacing: 8
        ) {
            ForEach(SymptomTag.allCases) { tag in
                Button {
                    toggle(tag)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tag.systemImageName)
                            .font(.caption.weight(.semibold))
                            .frame(width: 18)
                        Text(tag.displayName)
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer()
                    }
                    .foregroundStyle(selectedSymptoms.contains(tag) ? Color.white : Color.ccText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        selectedSymptoms.contains(tag) ? Color.ccPrimary : Color.ccSurface,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ tag: SymptomTag) {
        if selectedSymptoms.contains(tag) {
            selectedSymptoms.remove(tag)
        } else {
            selectedSymptoms.insert(tag)
        }
    }

    private func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let symptoms = SymptomTag.allCases.filter { selectedSymptoms.contains($0) }

        if let existing {
            existing.recordedAt = Calendar.current.startOfDay(for: recordedAt)
            existing.mood = mood
            existing.symptoms = symptoms
            existing.notes = trimmedNotes
            existing.editedAt = .now
            existing.authorAppleUserID = author.appleUserID
            existing.authorDisplayName = author.displayName
        } else {
            let entry = JournalEntry(
                recordedAt: recordedAt,
                mood: mood,
                symptoms: symptoms,
                notes: trimmedNotes,
                authorAppleUserID: author.appleUserID,
                authorDisplayName: author.displayName
            )
            entry.circle = circle
            modelContext.insert(entry)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = "Couldn't save. \(error.localizedDescription)"
            AppLogger.app.error(
                "Journal save failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func deleteExisting() {
        guard let existing else { return }
        modelContext.delete(existing)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = "Couldn't delete. \(error.localizedDescription)"
            AppLogger.app.error(
                "Journal delete failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
