import SwiftData
import SwiftUI

// MARK: - HealthRecordsView

/// Read-only browser over the clinical records the Care Recipient has
/// connected to Apple Health (MyChart / Epic, Cerner, …). Surfaces a
/// per-kind grouped list with a single "Pull from Apple Health" action
/// at the top. Newly imported records show in their kind's section.
///
/// **Empty state.** If HK is unavailable (Simulator, iPad without
/// HealthKit), we show an explainer instead of a confusing "0 records"
/// list. Same for the case where the user hasn't yet granted access.
///
/// **Privacy.** This view never sends FHIR payloads to the backend.
/// Records are local to CloudKit; export requires a future "share"
/// affordance, intentionally not in v1.
struct HealthRecordsView: View {
    let circle: Circle

    @Environment(\.modelContext) private var modelContext
    @Environment(HealthRecordsImporter.self) private var importer
    @State private var isPresentingDetail: HealthRecord?

    private var groupedRecords: [(HealthRecord.Kind, [HealthRecord])] {
        let grouped = Dictionary(grouping: circle.healthRecords) { $0.kind }
        return HealthRecord.Kind.allCases.compactMap { kind in
            guard let rows = grouped[kind], !rows.isEmpty else { return nil }
            return (kind, rows.sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) })
        }
    }

    var body: some View {
        List {
            Section {
                actionRow
            } footer: {
                if importer.isAvailable {
                    Text(
                        "Records are pulled from Apple Health. Connect a provider in the Health app → Browse → Health Records."
                    )
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
                } else {
                    Text("Apple Health isn't available on this device.")
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                }
            }

            if circle.healthRecords.isEmpty {
                Section {
                    emptyContent
                }
            } else {
                ForEach(groupedRecords, id: \.0) { kind, rows in
                    Section {
                        ForEach(rows) { record in
                            Button {
                                isPresentingDetail = record
                            } label: {
                                recordRow(record)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Image(systemName: kind.systemImageName)
                                .foregroundStyle(Color.ccPrimary)
                            Text(kind.displayName)
                                .font(.headline)
                                .foregroundStyle(Color.ccText)
                            Spacer()
                            Text("\(rows.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.ccSecondary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ccBackground)
        .navigationTitle("Health Records")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .sheet(item: $isPresentingDetail) { record in
            NavigationStack {
                HealthRecordDetailView(record: record)
            }
        }
        .refreshable { await importer.importAll(into: modelContext, circle: circle) }
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.title2)
                    .foregroundStyle(Color.ccPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Health")
                        .font(.headline)
                        .foregroundStyle(Color.ccText)
                    Text(importer.isRunning ? "Importing…" : statusLine)
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                }
                Spacer()
            }

            Button {
                Task {
                    do {
                        _ = try await importer.requestAuthorizationIfNeeded()
                    } catch {
                        // Surface auth failure via the status line.
                    }
                    await importer.importAll(into: modelContext, circle: circle)
                }
            } label: {
                Label(
                    importer.isRunning ? "Importing…" : "Pull from Apple Health",
                    systemImage: "square.and.arrow.down"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ccPrimary)
            .disabled(importer.isRunning || !importer.isAvailable)

            if let error = importer.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.ccDanger)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.ccPrimary.opacity(0.7))
            Text("No records yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.ccText)
            Text(
                "Tap **Pull from Apple Health** above. If nothing imports, connect a provider in the Health app first."
            )
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.ccSecondary)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func recordRow(_ record: HealthRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.displayTitle.isEmpty ? "Untitled" : record.displayTitle)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.ccText)
            if !record.displayDetail.isEmpty {
                Text(record.displayDetail)
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                if !record.sourceName.isEmpty {
                    Text(record.sourceName)
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
                if let occurredAt = record.occurredAt {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                    Text(occurredAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
                if !record.status.isEmpty {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                    Text(record.status.capitalized)
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var statusLine: String {
        if let lastImportAt = importer.lastImportAt {
            let when = lastImportAt.formatted(.relative(presentation: .named))
            return "Last imported \(when)"
        }
        return "Not yet imported"
    }
}

// MARK: - HealthRecordDetailView

struct HealthRecordDetailView: View {
    let record: HealthRecord

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !record.displayDetail.isEmpty {
                    section(title: "Detail", content: record.displayDetail)
                }
                if !record.status.isEmpty {
                    section(title: "Status", content: record.status.capitalized)
                }
                if !record.sourceName.isEmpty {
                    section(title: "Source", content: record.sourceName)
                }
                if let occurredAt = record.occurredAt {
                    section(
                        title: "Date",
                        content: occurredAt.formatted(date: .complete, time: .omitted)
                    )
                }
                if let prettyFHIR {
                    section(title: "FHIR resource", content: prettyFHIR, isMonospaced: true)
                }
            }
            .padding(Theme.spacing)
        }
        .background(Color.ccBackground)
        .navigationTitle(record.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: record.kind.systemImageName)
                .font(.title)
                .foregroundStyle(Color.ccPrimary)
                .frame(width: 44, height: 44)
                .background(Color.ccPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayTitle.isEmpty ? "Untitled" : record.displayTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Text(record.kind.displayName)
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            }
        }
    }

    private func section(title: String, content: String, isMonospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.ccSecondary)
                .textCase(.uppercase)
            Text(content)
                .font(isMonospaced ? .system(.footnote, design: .monospaced) : .body)
                .foregroundStyle(Color.ccText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.ccSurface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var prettyFHIR: String? {
        guard
            let data = record.fhirResourceData,
            let json = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let string = String(data: pretty, encoding: .utf8) else { return nil }
        return string
    }
}
