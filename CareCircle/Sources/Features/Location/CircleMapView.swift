import MapKit
import SwiftData
import SwiftUI
import UIKit

// MARK: - CircleMapView

/// Live map of every Circle member's last-known location. The Care
/// Recipient's pin is highlighted; caregivers see each other for
/// "who's nearby" coordination. The map auto-frames around every
/// sharing member, then a Recipient-locked button re-centers on the
/// person being cared for.
///
/// Sharing is opt-in per device — the bottom strip surfaces the
/// share toggle and, if needed, a deeplink into Settings to grant
/// the location permission.
struct CircleMapView: View {
    let authState: AuthState

    @Query(sort: \Circle.createdAt) private var circles: [Circle]
    @Query private var snapshots: [LocationSnapshot]
    @Environment(LocationSharingService.self) private var locationService
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var activeCircle: Circle? {
        guard case let .signedIn(user) = authState.status else {
            return circles.first
        }
        return circles.first(where: { $0.ownerAppleUserID == user.id }) ?? circles.first
    }

    private var circleSnapshots: [LocationSnapshot] {
        guard let circle = activeCircle else { return [] }
        return snapshots.filter { $0.circle?.id == circle.id }
    }

    private var recipientMemberID: String? {
        guard let circle = activeCircle else { return nil }
        let recipientMember = circle.members.first(where: { $0.role == .careRecipient && !$0.appleUserID.isEmpty })
        return recipientMember?.appleUserID
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                mapBody.ignoresSafeArea(edges: .bottom)
                controlPanel
            }
            .navigationTitle("Find")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar { trailingToolbar }
        }
        .task { initialFrame() }
        .onChange(of: circleSnapshots.count) { _, _ in initialFrame() }
    }

    private var mapBody: some View {
        Map(position: $cameraPosition) {
            ForEach(circleSnapshots, id: \.id) { snap in
                Annotation(
                    snap.memberDisplayName.isEmpty ? "Member" : snap.memberDisplayName,
                    coordinate: snap.coordinate
                ) {
                    memberMarker(snap)
                }
                .annotationTitles(.hidden)
            }
            if let recipient = recipientSnapshot {
                MapCircle(center: recipient.coordinate, radius: 150)
                    .foregroundStyle(Color.ccPrimary.opacity(0.10))
                    .stroke(Color.ccPrimary.opacity(0.45), lineWidth: 1.5)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapPitchToggle()
            MapCompass()
        }
    }

    @ToolbarContentBuilder
    private var trailingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                centerOnRecipient()
            } label: {
                Image(systemName: "person.fill.viewfinder")
                    .accessibilityLabel("Center on Care Recipient")
            }
            .disabled(recipientSnapshot == nil)
        }
    }

    private var controlPanel: some View {
        VStack(spacing: 8) {
            if circleSnapshots.isEmpty {
                emptyHint
            } else {
                memberStrip
            }
            shareCard
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.bottom, Theme.spacing)
    }

    private var emptyHint: some View {
        Text("No locations shared yet. Turn on sharing below — your Circle will start to populate the map.")
            .font(.caption)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }

    private var memberStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(circleSnapshots, id: \.id) { snap in
                    Button {
                        focus(on: snap)
                    } label: {
                        memberChip(snap)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func memberChip(_ snap: LocationSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                SwiftUI.Circle()
                    .fill(snap.isSharingEnabled ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text(snap.memberDisplayName.isEmpty ? "Member" : snap.memberDisplayName)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.ccText)
            Text(VitalFormatting.relativeRecordedAt(snap.recordedAt))
                .font(.system(size: 10))
                .foregroundStyle(Color.ccSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(.thickMaterial)
        )
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share my location")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ccText)
                    Text(shareSubtitle)
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
                Spacer(minLength: 0)
                @Bindable var binding = locationService
                Toggle("", isOn: $binding.shareLocation)
                    .labelsHidden()
                    .tint(Color.ccPrimary)
            }
            permissionAction
        }
        .padding(Theme.spacing)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }

    @ViewBuilder
    private var permissionAction: some View {
        if locationService.authorizationStatus == .denied {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.ccPrimary)
        } else if locationService.authorizationStatus == .notDetermined {
            Button("Grant access") {
                locationService.requestAuthorization()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.ccPrimary)
        }
    }

    private var shareSubtitle: String {
        switch locationService.authorizationStatus {
        case .authorizedAlways: "Always sharing while signed in."
        case .authorizedWhenInUse: "Sharing while the app is open. Upgrade to Always for background updates."
        case .denied, .restricted: "Location denied. Open Settings to enable."
        case .notDetermined: "Sharing not yet authorized."
        @unknown default: "Sharing status unknown."
        }
    }

    private func memberMarker(_ snap: LocationSnapshot) -> some View {
        let isRecipient = snap.memberAppleUserID == recipientMemberID
        return ZStack {
            SwiftUI.Circle()
                .fill(isRecipient ? Color.ccPrimary : Color.ccText)
                .frame(width: 32, height: 32)
            Image(systemName: isRecipient ? "heart.fill" : "person.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        .overlay(alignment: .bottom) {
            SwiftUI.Circle()
                .fill(snap.isSharingEnabled ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .overlay(SwiftUI.Circle().stroke(.white, lineWidth: 1.5))
                .offset(y: 4)
        }
    }

    private var recipientSnapshot: LocationSnapshot? {
        guard let id = recipientMemberID else { return nil }
        return circleSnapshots.first(where: { $0.memberAppleUserID == id })
    }

    private func initialFrame() {
        guard !circleSnapshots.isEmpty else { return }
        let coords = circleSnapshots.map(\.coordinate)
        if coords.count == 1, let single = coords.first {
            cameraPosition = .region(MKCoordinateRegion(
                center: single,
                latitudinalMeters: 800,
                longitudinalMeters: 800
            ))
        } else {
            cameraPosition = .region(MKCoordinateRegion(coordinates: coords))
        }
    }

    private func centerOnRecipient() {
        guard let recipient = recipientSnapshot else { return }
        focus(on: recipient)
    }

    private func focus(on snap: LocationSnapshot) {
        cameraPosition = .region(MKCoordinateRegion(
            center: snap.coordinate,
            latitudinalMeters: 600,
            longitudinalMeters: 600
        ))
    }
}

// MARK: - Helpers

extension LocationSnapshot {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension MKCoordinateRegion {
    init(coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else {
            self.init()
            return
        }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.5)
        )
        self.init(center: center, span: span)
    }
}
