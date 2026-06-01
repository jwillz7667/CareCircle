import MapKit
import SwiftData
import SwiftUI

// MARK: - SOSDetailView

/// Inspector for a single SOSEvent. Shows trigger metadata, an optional
/// Map snapshot if location was captured, and a "Call primary contact"
/// CTA wired to `tel://`. Resolution notes editor + "Mark resolved" CTA
/// persist via SwiftData; CloudKit handles the fan-out.
struct SOSDetailView: View {
    @Bindable var event: SOSEvent
    let viewerAppleUserID: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(SOSCenter.self) private var sosCenter

    @State private var notesDraft = ""
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var primaryContact: EmergencyContact? {
        event.circle?.emergencyContacts
            .first(where: \.isPrimary)
    }

    var body: some View {
        Form {
            Section {
                statusRow
                labeledRow("Triggered by", value: event.triggeredByDisplayName)
                labeledRow(
                    "Triggered at",
                    value: event.triggeredAt.formatted(date: .abbreviated, time: .shortened)
                )
                if let canceledAt = event.canceledAt {
                    labeledRow(
                        "Canceled at",
                        value: canceledAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                if let resolvedAt = event.resolvedAt {
                    labeledRow(
                        "Resolved at",
                        value: resolvedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }

            if event.hasLocation {
                Section("Location") { mapPreview }
            }

            primaryContactSection

            if event.status == .active {
                resolutionSection
            } else if let notes = event.resolutionNotes, !notes.isEmpty {
                Section("Resolution notes") {
                    Text(notes).foregroundStyle(Color.ccText)
                }
            }
        }
        .navigationTitle("SOS detail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            notesDraft = event.resolutionNotes ?? ""
            if event.hasLocation, let coord = locationCoordinate {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coord,
                        latitudinalMeters: 600,
                        longitudinalMeters: 600
                    )
                )
            }
        }
    }

    // MARK: Sections

    private var statusRow: some View {
        HStack {
            Text("Status")
                .foregroundStyle(Color.ccSecondary)
            Spacer()
            StatusPill(status: event.status)
        }
    }

    private func labeledRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.ccSecondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Color.ccText)
        }
    }

    @ViewBuilder
    private var mapPreview: some View {
        if let coord = locationCoordinate {
            Map(position: $cameraPosition) {
                Marker("Trigger", coordinate: coord)
                    .tint(.red)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .accessibilityLabel(
                "Map of SOS location at latitude \(coord.latitude), longitude \(coord.longitude)"
            )
            if let accuracy = event.locationAccuracyMeters {
                Text("Accuracy ±\(Int(accuracy)) m")
                    .font(.caption)
                    .foregroundStyle(Color.ccSecondary)
            }
        }
    }

    private var primaryContactSection: some View {
        Section("Primary contact") {
            if let contact = primaryContact {
                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.name).font(.headline)
                    if let relationship = contact.relationship, !relationship.isEmpty {
                        Text(relationship)
                            .font(.subheadline)
                            .foregroundStyle(Color.ccSecondary)
                    }
                    Text(contact.phoneE164)
                        .font(.subheadline)
                        .foregroundStyle(Color.ccSecondary)
                }
                Button {
                    callPrimary(contact)
                } label: {
                    Label("Call \(contact.name)", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.ccPrimary)
                .tint(.red)
            } else {
                Text("No primary contact configured.")
                    .foregroundStyle(Color.ccSecondary)
            }
        }
    }

    private var resolutionSection: some View {
        Section("Resolution") {
            TextField(
                "Resolution notes (optional)",
                text: $notesDraft,
                axis: .vertical
            )
            .lineLimit(3 ... 6)
            Button {
                markResolved()
            } label: {
                Label("Mark resolved", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.ccPrimary)
        }
    }

    // MARK: Actions

    private var locationCoordinate: CLLocationCoordinate2D? {
        guard let lat = event.latitude, let lon = event.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func callPrimary(_ contact: EmergencyContact) {
        let sanitized = contact.phoneE164
            .filter { $0.isNumber || $0 == "+" }
        guard
            !sanitized.isEmpty,
            let url = URL(string: "tel://\(sanitized)") else { return }
        event.primaryContactCalled = true
        try? modelContext.save()
        openURL(url)
    }

    private func markResolved() {
        let trimmed = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        sosCenter.resolve(
            event,
            by: viewerAppleUserID,
            notes: trimmed.isEmpty ? nil : trimmed,
            in: modelContext
        )
    }
}

// MARK: - StatusPill

private struct StatusPill: View {
    let status: SOSStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch status {
        case .active: .red
        case .canceled: .gray.opacity(0.3)
        case .resolved: .green.opacity(0.25)
        }
    }

    private var foreground: Color {
        switch status {
        case .active: .white
        case .canceled: Color.ccSecondary
        case .resolved: .green
        }
    }
}
