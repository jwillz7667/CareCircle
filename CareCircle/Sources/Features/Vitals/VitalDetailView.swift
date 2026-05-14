import SwiftData
import SwiftUI

// MARK: - VitalDetailView

/// Full detail screen for a single vital. Shows the value, kind,
/// timestamp, source, recorder, and notes. Recorders can delete
/// their own readings via the toolbar — deletes go through the
/// backend so other devices see the row disappear on the next
/// hydration pass.
struct VitalDetailView: View {
    let vital: Vital
    let circle: Circle
    let author: ActivityAuthorContext

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(BackendRealtimeClient.self) private var realtimeClient
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    private var canDelete: Bool {
        vital.recordedByAppleUserID == author.appleUserID
    }

    var body: some View {
        scrollBody
            .background(Color.ccBackground)
            .navigationTitle(vital.kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar { deleteToolbarItem }
            .confirmationDialog(
                "Delete this reading?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { Task { await delete() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove the reading from every device in your Circle.")
            }
            .overlay { deletingOverlay }
            .alert(
                "Couldn't delete",
                isPresented: Binding(
                    get: { deleteError != nil },
                    set: { if !$0 { deleteError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
    }

    private var scrollBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header
                valueCard
                metadataCard
                if let notes = vital.notes, !notes.isEmpty {
                    notesCard(notes)
                }
                DisclaimerFooter()
                    .padding(.top, Theme.spacing)
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, Theme.spacing)
        }
    }

    @ToolbarContentBuilder
    private var deleteToolbarItem: some ToolbarContent {
        if canDelete {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete reading")
            }
        }
    }

    @ViewBuilder
    private var deletingOverlay: some View {
        if isDeleting {
            ProgressView()
                .controlSize(.large)
                .padding(Theme.spacing)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        }
    }

    private var header: some View {
        HStack(spacing: Theme.spacing) {
            ZStack {
                SwiftUI.Circle()
                    .fill(vital.kind.tintColor.opacity(0.2))
                Image(systemName: vital.kind.systemImageName)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(vital.kind.tintColor)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(vital.kind.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Text(VitalFormatting.absoluteRecordedAt(vital.recordedAt))
                    .font(.subheadline)
                    .foregroundStyle(Color.ccSecondary)
            }
        }
    }

    private var valueCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(VitalFormatting.formattedValue(vital))
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ccText)
            Text(vital.unit)
                .font(.headline)
                .foregroundStyle(Color.ccSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(Color.ccSurface)
        )
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            metadataRow(label: "Source", value: vital.source.displayName, icon: vital.source.systemImageName)
            metadataRow(
                label: "Recorded by",
                value: recorderDisplay,
                icon: "person.fill"
            )
            metadataRow(
                label: "Recorded at",
                value: VitalFormatting.absoluteRecordedAt(vital.recordedAt),
                icon: "clock.fill"
            )
        }
        .padding(Theme.spacing)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(Color.ccSurface)
        )
    }

    private func metadataRow(label: String, value: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.tightSpacing) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(Color.ccSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.ccSecondary)
                Text(value)
                    .font(.body)
                    .foregroundStyle(Color.ccText)
            }
        }
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            Text("Notes")
                .font(.caption)
                .foregroundStyle(Color.ccSecondary)
            Text(notes)
                .font(.body)
                .foregroundStyle(Color.ccText)
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(Color.ccSurface)
        )
    }

    private var recorderDisplay: String {
        if !vital.recordedByDisplayName.isEmpty { return vital.recordedByDisplayName }
        if vital.recordedByAppleUserID == author.appleUserID { return author.displayName }
        return circle.members
            .first(where: { $0.appleUserID == vital.recordedByAppleUserID })?
            .displayName ?? "Member"
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await realtimeClient.apiClient.sendNoResponse(
                method: HTTPMethod.delete,
                path: "/v1/vitals/\(vital.id.uuidString.lowercased())",
                authenticated: true
            )
            modelContext.delete(vital)
            try? modelContext.save()
            dismiss()
        } catch {
            deleteError = error.errorDescription ?? "Try again."
        }
    }
}
