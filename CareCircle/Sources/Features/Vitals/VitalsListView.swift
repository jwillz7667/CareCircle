import SwiftData
import SwiftUI

// MARK: - VitalsListView

/// Chronological list of vitals readings for a Circle. The caregiver
/// (or Care Recipient, for self-recorded readings) uses this to scan
/// recent vitals, filter by kind, and add a new manual reading.
/// HealthKit-imported rows share the same list — they're disambiguated
/// from manual entries by a heart-icon badge on the row.
struct VitalsListView: View {
    let circle: Circle
    let author: ActivityAuthorContext

    @Environment(\.modelContext) private var modelContext
    @Environment(BackendRealtimeClient.self) private var realtimeClient
    @State private var isAdding = false
    @State private var selectedKind: VitalKind?

    private var permissions: CirclePermissions {
        CirclePermissions.resolve(circle: circle, appleUserID: author.appleUserID)
    }

    private var allVitals: [Vital] {
        circle.vitals.sorted { $0.recordedAt > $1.recordedAt }
    }

    private var filtered: [Vital] {
        guard let selectedKind else { return allVitals }
        return allVitals.filter { $0.kind == selectedKind }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            scrollContent
            if permissions.canPostActivity {
                addButton
                    .padding(.trailing, Theme.spacing)
                    .padding(.bottom, Theme.spacing)
            }
        }
        .background(Color.ccBackground)
        .navigationTitle("Vitals")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .sheet(isPresented: $isAdding) {
            VitalsAddView(circle: circle, author: author)
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                kindFilter
                if filtered.isEmpty {
                    emptyState
                        .padding(.top, Theme.looseSpacing)
                } else {
                    LazyVStack(spacing: Theme.tightSpacing) {
                        ForEach(filtered) { vital in
                            NavigationLink {
                                VitalDetailView(
                                    vital: vital,
                                    circle: circle,
                                    author: author
                                )
                            } label: {
                                VitalRow(
                                    vital: vital,
                                    recorderDisplayName: recorderName(for: vital)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                DisclaimerFooter()
                    .padding(.top, Theme.looseSpacing)
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.top, Theme.spacing)
            .padding(.bottom, 96)
        }
        .refreshable {
            await realtimeClient.snapshotResync(
                circleIds: [circle.id],
                modelContext: modelContext
            )
        }
    }

    private var kindFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", systemImage: nil, isSelected: selectedKind == nil) {
                    selectedKind = nil
                }
                ForEach(presentKinds, id: \.self) { kind in
                    chip(
                        title: kind.shortName,
                        systemImage: kind.systemImageName,
                        isSelected: selectedKind == kind
                    ) {
                        selectedKind = selectedKind == kind ? nil : kind
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var presentKinds: [VitalKind] {
        let kinds = Set(allVitals.map(\.kind))
        return VitalKind.allCases.filter { kinds.contains($0) }
    }

    private func chip(
        title: String,
        systemImage: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    )
        -> some View
    {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.footnote.weight(.medium))
                }
                Text(title)
                    .font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isSelected ? Color.ccPrimary : Color.ccSurface)
            )
            .foregroundStyle(isSelected ? Color.white : Color.ccText)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacing) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.ccPrimary)
            Text(selectedKind == nil ? "No vitals yet." : "No \(selectedKind?.displayName.lowercased() ?? "") readings.")
                .font(.headline)
                .foregroundStyle(Color.ccText)
            Text(permissions.canPostActivity
                ? "Add a manual reading, or connect Apple Health to import samples automatically."
                : "Readings recorded by caregivers will appear here.")
                .font(.subheadline)
                .foregroundStyle(Color.ccSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.looseSpacing)
        }
        .padding(.vertical, Theme.looseSpacing)
    }

    private var addButton: some View {
        Button {
            isAdding = true
        } label: {
            Label("Add reading", systemImage: "plus")
                .font(.body.weight(.semibold))
                .padding(.horizontal, Theme.spacing)
                .padding(.vertical, 12)
                .foregroundStyle(Color.white)
                .background(Capsule().fill(Color.ccPrimary))
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 4)
        }
        .accessibilityHint("Add a new vitals reading.")
    }

    private func recorderName(for vital: Vital) -> String? {
        if !vital.recordedByDisplayName.isEmpty { return vital.recordedByDisplayName }
        if vital.recordedByAppleUserID == author.appleUserID { return author.displayName }
        return circle.members
            .first(where: { $0.appleUserID == vital.recordedByAppleUserID })?
            .displayName
    }
}
