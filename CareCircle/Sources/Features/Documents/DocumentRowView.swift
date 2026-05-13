import SwiftUI

// MARK: - DocumentRowView

/// Compact row used in `DocumentListView`. Shows the type glyph, title,
/// size, and an expiry chip when present.
struct DocumentRowView: View {
    let document: Document

    var body: some View {
        HStack(spacing: Theme.spacing) {
            iconBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title.isEmpty ? "Untitled document" : document.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ccText)

                HStack(spacing: 6) {
                    Text(document.type.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Color.ccSecondary)
                    Text("·").foregroundStyle(Color.ccSecondary)
                    Text(sizeDescription)
                        .font(.subheadline)
                        .foregroundStyle(Color.ccSecondary)
                }

                if let expiresAt = document.expiresAt {
                    Label(expiryDescription(from: expiresAt), systemImage: "calendar.badge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(expiryColor(from: expiresAt))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Theme.tightSpacing / 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.ccSurface)
                .frame(width: 44, height: 44)
            Image(systemName: document.type.systemImageName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.ccPrimary)
                .accessibilityHidden(true)
        }
    }

    private var sizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(document.sizeBytes))
    }

    private func expiryDescription(from date: Date) -> String {
        if date < Date() {
            return "Expired \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Expires \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func expiryColor(from date: Date) -> Color {
        date < Date() ? Color.ccDanger : Color.ccSecondary
    }

    private var accessibilityDescription: String {
        var parts: [String] = [document.title, document.type.displayName, sizeDescription]
        if let expiresAt = document.expiresAt {
            parts.append(expiryDescription(from: expiresAt))
        }
        return parts.joined(separator: ", ")
    }
}
