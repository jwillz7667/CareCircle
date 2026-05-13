import SwiftUI

// MARK: - ExtractionDisplayState

enum ExtractionDisplayState: Equatable {
    case loading
    case unsupported
    case ready(ExtractedEntities)
    case hidden
}

// MARK: - ExtractedEntitiesView

struct ExtractedEntitiesView: View {
    let state: ExtractionDisplayState
    var compact = false

    var body: some View {
        switch state {
        case .loading:
            loadingChip

        case .unsupported:
            EmptyView()

        case let .ready(entities):
            if entities.isEmpty {
                EmptyView()
            } else {
                chips(for: entities)
            }

        case .hidden:
            EmptyView()
        }
    }

    private var loadingChip: some View {
        Label("Reading…", systemImage: "sparkles")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.ccSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.ccSurface)
            )
    }

    @ViewBuilder
    private func chips(for entities: ExtractedEntities) -> some View {
        let groups = ChipGroup.groups(for: entities)
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            if !compact, let summary = entities.summary, !summary.isEmpty {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            }

            FlowLayout(spacing: 6, runSpacing: 6) {
                ForEach(groups) { group in
                    ForEach(group.entries) { chip in
                        ExtractedEntityChip(
                            kind: group.kind,
                            label: chip.label,
                            detail: chip.detail,
                            confidence: chip.confidence
                        )
                    }
                }
            }
        }
    }
}

// MARK: - ExtractedEntityChip

private struct ExtractedEntityChip: View {
    let kind: ChipKind
    let label: String
    let detail: String?
    let confidence: ExtractionConfidence

    @State private var isShowingInfo = false

    var body: some View {
        Button {
            if kind == .medication { isShowingInfo = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kind.systemImage)
                    .font(.caption2.weight(.semibold))
                Text(label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text("· \(detail)")
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(kind.foreground.opacity(0.8))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(kind.background)
            )
            .foregroundStyle(kind.foreground)
            .opacity(confidence == .low ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(kind == .medication ? "Tap for medication disclaimer." : "")
        .alert(
            "Not medical advice",
            isPresented: $isShowingInfo
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Consult your healthcare provider before changing medications.")
        }
    }

    private var accessibilityLabel: String {
        var pieces = ["\(kind.spokenName): \(label)"]
        if let detail, !detail.isEmpty {
            pieces.append(detail)
        }
        pieces.append("\(confidence.rawValue) confidence")
        return pieces.joined(separator: ", ")
    }
}

// MARK: - ChipKind

private enum ChipKind: Equatable {
    case medication
    case vital
    case appointment
    case meal
    case symptom
    case generalNote

    var systemImage: String {
        switch self {
        case .medication: "pills.fill"
        case .vital: "heart.fill"
        case .appointment: "calendar"
        case .meal: "fork.knife"
        case .symptom: "stethoscope"
        case .generalNote: "note.text"
        }
    }

    var foreground: Color {
        switch self {
        case .medication: Color.ccPrimary
        case .vital: Color.ccDanger
        case .appointment: Color.ccPrimary
        case .meal: Color.ccText
        case .symptom: Color.ccText
        case .generalNote: Color.ccSecondary
        }
    }

    var background: Color {
        switch self {
        case .medication: Color.ccPrimary.opacity(0.12)
        case .vital: Color.ccDanger.opacity(0.12)
        case .appointment: Color.ccPrimary.opacity(0.08)
        case .meal: Color.ccSurface
        case .symptom: Color.ccSurface
        case .generalNote: Color.ccSurface
        }
    }

    var spokenName: String {
        switch self {
        case .medication: "Medication"
        case .vital: "Vital"
        case .appointment: "Appointment"
        case .meal: "Meal"
        case .symptom: "Symptom"
        case .generalNote: "Note"
        }
    }
}

// MARK: - ChipGroup

private struct ChipGroup: Identifiable {
    struct Entry: Identifiable {
        var id: UUID
        var label: String
        var detail: String?
        var confidence: ExtractionConfidence
    }

    var id: String {
        kind.spokenName
    }

    var kind: ChipKind
    var entries: [Entry]

    static func groups(for entities: ExtractedEntities) -> [ChipGroup] {
        let pairs: [(ChipKind, [ExtractedEntity])] = [
            (.medication, entities.medications),
            (.vital, entities.vitals),
            (.appointment, entities.appointments),
            (.symptom, entities.symptoms),
            (.meal, entities.meals),
            (.generalNote, entities.generalNotes),
        ]
        return pairs.compactMap { kind, list in
            guard !list.isEmpty else { return nil }
            let entries = list.map { entity in
                Entry(
                    id: entity.id,
                    label: entity.name,
                    detail: entity.details,
                    confidence: entity.confidence
                )
            }
            return ChipGroup(kind: kind, entries: entries)
        }
    }
}

// MARK: - FlowLayout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var runSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let layout = computeLayout(width: width, subviews: subviews)
        return CGSize(width: layout.width, height: layout.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let layout = computeLayout(width: bounds.width, subviews: subviews)
        for placement in layout.placements {
            let origin = CGPoint(
                x: bounds.minX + placement.origin.x,
                y: bounds.minY + placement.origin.y
            )
            subviews[placement.index].place(
                at: origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private struct Placement {
        var index: Int
        var origin: CGPoint
        var size: CGSize
    }

    private struct Computed {
        var width: CGFloat
        var height: CGFloat
        var placements: [Placement]
    }

    private func computeLayout(width: CGFloat, subviews: Subviews) -> Computed {
        var placements: [Placement] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + runSpacing
                rowHeight = 0
            }
            placements.append(Placement(
                index: index,
                origin: CGPoint(x: x, y: y),
                size: size
            ))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxWidth = max(maxWidth, x - spacing)
        }
        return Computed(
            width: maxWidth,
            height: y + rowHeight,
            placements: placements
        )
    }
}
