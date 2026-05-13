import SwiftData
import SwiftUI

// MARK: - CareMinuteListView

/// Calendar-week-pivoted list of paid care entries. The Circle owner can
/// see every member's entries; everyone else sees their own. Week
/// navigation is locale-aware via `CareMinuteService.weekRange`.
struct CareMinuteListView: View {
    let circle: Circle
    let viewerAppleUserID: String

    @State private var weekAnchor: Date = .now
    @State private var isAdding = false
    @State private var isExporting = false

    private var canSeeAllMembers: Bool {
        circle.ownerAppleUserID == viewerAppleUserID
    }

    private var weekRange: Range<Date> {
        CareMinuteService.weekRange(containing: weekAnchor)
    }

    private var allEntriesThisWeek: [CareMinuteEntry] {
        CareMinuteService.entries(in: weekRange, from: circle.careMinuteEntries)
    }

    private var visibleEntries: [CareMinuteEntry] {
        canSeeAllMembers
            ? allEntriesThisWeek
            : allEntriesThisWeek.filter { $0.caregiverAppleUserID == viewerAppleUserID }
    }

    private var groupedByDay: [(day: Date, entries: [CareMinuteEntry])] {
        CareMinuteService.groupedByDay(visibleEntries)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content

            addButton
                .padding(.trailing, Theme.spacing)
                .padding(.bottom, Theme.spacing)
        }
        .background(Color.ccBackground)
        .navigationTitle("Care minutes")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isExporting = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(visibleEntries.isEmpty)
            }
        }
        .sheet(isPresented: $isAdding) {
            AddCareMinuteEntryView(
                circle: circle,
                viewerAppleUserID: viewerAppleUserID,
                viewerDisplayName: viewerDisplayName,
                anchorDate: weekAnchor
            )
        }
        .sheet(isPresented: $isExporting) {
            CareMinuteExportView(
                circle: circle,
                viewerAppleUserID: viewerAppleUserID,
                initialAnchor: weekAnchor
            )
        }
    }

    private var viewerDisplayName: String {
        circle.members.first(where: { $0.appleUserID == viewerAppleUserID })?.displayName ?? ""
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                weekNavigator
                summaryCard

                if visibleEntries.isEmpty {
                    emptyState
                } else {
                    entriesList
                }

                disclaimerFooter
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.top, Theme.spacing)
            .padding(.bottom, Theme.looseSpacing * 2)
        }
    }

    private var weekNavigator: some View {
        HStack {
            Button {
                shiftWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .padding(10)
                    .background(Color.ccSurface.clipShape(.circle))
                    .foregroundStyle(Color.ccText)
            }
            .accessibilityLabel("Previous week")

            Spacer()

            VStack(spacing: 2) {
                Text(weekTitle)
                    .font(.headline)
                    .foregroundStyle(Color.ccText)
                Text(weekRangeLabel)
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            }

            Spacer()

            Button {
                shiftWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .padding(10)
                    .background(Color.ccSurface.clipShape(.circle))
                    .foregroundStyle(isFutureWeek ? Color.ccSecondary : Color.ccText)
            }
            .disabled(isFutureWeek)
            .accessibilityLabel("Next week")
        }
    }

    private var summaryCard: some View {
        CareMinuteSummaryCard(
            entries: visibleEntries,
            scopeLabel: canSeeAllMembers ? nil : "Your entries"
        )
    }

    private var entriesList: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            ForEach(groupedByDay, id: \.day) { group in
                VStack(alignment: .leading, spacing: Theme.tightSpacing) {
                    Text(dayHeader(for: group.day))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ccSecondary)
                        .padding(.horizontal, Theme.tightSpacing)

                    VStack(spacing: 0) {
                        ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                            NavigationLink {
                                CareMinuteEntryDetailView(
                                    entry: entry,
                                    viewerAppleUserID: viewerAppleUserID,
                                    canManage: canManage(entry)
                                )
                            } label: {
                                CareMinuteRowView(
                                    entry: entry,
                                    showsCaregiver: canSeeAllMembers
                                )
                            }
                            .buttonStyle(.plain)

                            if index < group.entries.count - 1 {
                                Divider().padding(.leading, Theme.spacing)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .fill(Color.ccSurface)
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.tightSpacing) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.ccPrimary)
            Text("No entries this week")
                .font(.headline)
                .foregroundStyle(Color.ccText)
            Text("Tap the plus button to log time on care tasks.")
                .font(.subheadline)
                .foregroundStyle(Color.ccSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.looseSpacing)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .stroke(Color.ccSecondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
    }

    private var disclaimerFooter: some View {
        Text(
            "Not a direct submission to any fiscal intermediary — " +
                "verify against your FI's requirements before submitting."
        )
        .font(.caption)
        .foregroundStyle(Color.ccSecondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.tightSpacing)
    }

    private var addButton: some View {
        Button {
            isAdding = true
        } label: {
            Label("Log time", systemImage: "plus")
                .font(.body.weight(.semibold))
                .padding(.horizontal, Theme.spacing)
                .padding(.vertical, 12)
                .foregroundStyle(Color.white)
                .background(Capsule().fill(Color.ccPrimary))
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 4)
        }
        .accessibilityHint("Log a new block of care time for this Circle.")
    }

    private func canManage(_ entry: CareMinuteEntry) -> Bool {
        entry.caregiverAppleUserID == viewerAppleUserID
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

    private var weekTitle: String {
        let calendar = Calendar.current
        let nowWeek = CareMinuteService.weekRange(containing: .now)
        if calendar.isDate(weekRange.lowerBound, inSameDayAs: nowWeek.lowerBound) {
            return "This week"
        }
        guard let lastWeekAnchor = calendar.date(byAdding: .weekOfYear, value: -1, to: .now) else {
            return "Week"
        }
        let lastWeek = CareMinuteService.weekRange(containing: lastWeekAnchor)
        if calendar.isDate(weekRange.lowerBound, inSameDayAs: lastWeek.lowerBound) {
            return "Last week"
        }
        return "Week"
    }

    private var weekRangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: -1, to: weekRange.upperBound) ?? weekRange.upperBound
        return "\(formatter.string(from: weekRange.lowerBound)) – \(formatter.string(from: end))"
    }

    private func dayHeader(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
}
