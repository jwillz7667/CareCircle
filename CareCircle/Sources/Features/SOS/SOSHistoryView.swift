import SwiftData
import SwiftUI

// MARK: - SOSHistoryView

struct SOSHistoryView: View {
    let circle: Circle
    let viewerAppleUserID: String

    private var events: [SOSEvent] {
        (circle.sosEvents).sorted { $0.triggeredAt > $1.triggeredAt }
    }

    var body: some View {
        Group {
            if events.isEmpty {
                EmptyStateView(
                    systemImage: "sos.circle",
                    title: "No SOS history",
                    message: "Past SOS events will appear here once triggered."
                )
            } else {
                List(events, id: \.id) { event in
                    NavigationLink {
                        SOSDetailView(event: event, viewerAppleUserID: viewerAppleUserID)
                    } label: {
                        eventRow(for: event)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("SOS history")
        .navigationBarTitleDisplayMode(.large)
        .background(Color.ccBackground)
    }

    private func eventRow(for event: SOSEvent) -> some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            HStack {
                Text(event.triggeredByDisplayName)
                    .font(.headline)
                    .foregroundStyle(Color.ccText)
                Spacer()
                StatusBadge(status: event.status)
            }
            Text(event.triggeredAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(Color.ccSecondary)
            if event.hasLocation {
                Label("Location captured", systemImage: "location.fill")
                    .font(.caption)
                    .foregroundStyle(Color.ccSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - StatusBadge

private struct StatusBadge: View {
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
