import OSLog
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - CareMinuteExportView

/// Pick a week, preview the generated PDF, share via the system sheet.
/// When the share is dispatched, every entry in the rendered week is
/// marked `exportedAt = .now` so the in-app row can show the "exported"
/// chip. Re-exporting the same week refreshes the timestamp.
struct CareMinuteExportView: View {
    let circle: Circle
    let viewerAppleUserID: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var weekAnchor: Date
    @State private var pdfData: Data?
    @State private var errorMessage: String?
    @State private var isMarkingExported = false

    init(circle: Circle, viewerAppleUserID: String, initialAnchor: Date = .now) {
        self.circle = circle
        self.viewerAppleUserID = viewerAppleUserID
        _weekAnchor = State(initialValue: initialAnchor)
    }

    private var weekRange: Range<Date> {
        CareMinuteService.weekRange(containing: weekAnchor)
    }

    private var entries: [CareMinuteEntry] {
        let inWeek = CareMinuteService.entries(in: weekRange, from: circle.careMinuteEntries)
        return canSeeAllMembers ? inWeek : inWeek.filter { $0.caregiverAppleUserID == viewerAppleUserID }
    }

    private var canSeeAllMembers: Bool {
        circle.ownerAppleUserID == viewerAppleUserID
    }

    private var viewerDisplayName: String {
        circle.members.first(where: { $0.appleUserID == viewerAppleUserID })?.displayName ?? ""
    }

    private var filename: String {
        CareMinuteService.exportFilename(for: weekRange, circleName: circle.name)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekPicker
                    .padding(Theme.spacing)
                    .background(Color.ccSurface)

                if entries.isEmpty {
                    emptyState
                } else if let pdfData {
                    PDFPreview(data: pdfData)
                        .background(Color.ccBackground)
                } else {
                    generatePrompt
                }
            }
            .background(Color.ccBackground)
            .navigationTitle("Export PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar { toolbar }
            .onAppear {
                regenerateIfNeeded()
            }
            .onChange(of: weekAnchor) { _, _ in
                pdfData = nil
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if let pdfData {
                ShareLink(
                    item: PDFExportArtifact(data: pdfData, filename: filename),
                    preview: SharePreview(filename, image: Image(systemName: "doc.text"))
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .simultaneousGesture(TapGesture().onEnded { markEntriesExported() })
            }
        }
    }

    private var weekPicker: some View {
        HStack {
            Button {
                shiftWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .padding(8)
                    .background(Color.ccBackground.clipShape(.circle))
                    .foregroundStyle(Color.ccText)
            }
            .accessibilityLabel("Previous week")

            Spacer()

            VStack(spacing: 2) {
                Text(weekRangeLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Text("\(entries.count) entries · \(CareMinuteService.totalHoursFormatted(in: entries))")
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            }

            Spacer()

            Button {
                shiftWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .padding(8)
                    .background(Color.ccBackground.clipShape(.circle))
                    .foregroundStyle(isFutureWeek ? Color.ccSecondary : Color.ccText)
            }
            .disabled(isFutureWeek)
            .accessibilityLabel("Next week")
        }
    }

    private var generatePrompt: some View {
        VStack(spacing: Theme.spacing) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.ccPrimary)
            Button("Generate PDF") {
                regenerate()
            }
            .buttonStyle(PrimaryButtonStyle())
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.ccDanger)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.looseSpacing)
        .background(Color.ccBackground)
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "calendar.badge.exclamationmark",
            title: "Nothing to export",
            message: "No care minutes were logged this week."
        )
    }

    // MARK: - Helpers

    private func regenerateIfNeeded() {
        if pdfData == nil, !entries.isEmpty {
            regenerate()
        }
    }

    private func regenerate() {
        let context = CareMinutePDFRenderer.Context(
            circleName: circle.name,
            recipientName: circle.careRecipient?.fullName,
            caregiverDisplayName: viewerDisplayName,
            fiscalIntermediary: entries.first?.fiscalIntermediary,
            weekRange: weekRange,
            entries: entries
        )
        pdfData = CareMinutePDFRenderer.render(context)
    }

    private func markEntriesExported() {
        guard !isMarkingExported else { return }
        isMarkingExported = true
        defer { isMarkingExported = false }

        let now = Date.now
        for entry in entries where entry.caregiverAppleUserID == viewerAppleUserID {
            entry.exportedAt = now
            entry.updatedAt = now
        }
        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error(
                "Failed to stamp exportedAt: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func shiftWeek(by weeks: Int) {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .weekOfYear, value: weeks, to: weekAnchor) else { return }
        weekAnchor = next
    }

    private var isFutureWeek: Bool {
        let nextWeek = CareMinuteService.weekRange(containing: Date.now).upperBound
        return weekRange.lowerBound >= nextWeek
    }

    private var weekRangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: -1, to: weekRange.upperBound) ?? weekRange.upperBound
        return "\(formatter.string(from: weekRange.lowerBound)) – \(formatter.string(from: end))"
    }
}

// MARK: - PDFPreview

private struct PDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context _: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context _: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}

// MARK: - PDFExportArtifact

/// Transferable wrapper so `ShareLink` writes a real `.pdf` file to the
/// share-sheet pasteboard / target app instead of a `Data` blob.
private struct PDFExportArtifact: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { artifact in
            artifact.data
        }
        .suggestedFileName { $0.filename }
    }
}
