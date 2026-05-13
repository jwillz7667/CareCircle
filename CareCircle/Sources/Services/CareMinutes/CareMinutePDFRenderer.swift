import Foundation
import UIKit

// MARK: - CareMinutePDFRenderer

/// Renders a one-page (or multi-page if needed) Letter-sized PDF formatted
/// as a generic fiscal-intermediary timesheet. v1 ships a single layout
/// that takes "ready-to-edit" precedence over "matches your FI exactly" —
/// per-FI templates (PPL, Acumen, Easterseals) become per-overlay
/// renderers if/when we land a paying FI partner.
enum CareMinutePDFRenderer {
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let horizontalMargin: CGFloat = 36
    private static let topMargin: CGFloat = 48

    struct Context {
        let circleName: String
        let recipientName: String?
        let caregiverDisplayName: String
        let fiscalIntermediary: String?
        let weekRange: Range<Date>
        let entries: [CareMinuteEntry]
    }

    static func render(_ context: Context) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "CareCircle",
            kCGPDFContextTitle as String: "Care minutes — \(context.circleName)",
        ]
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

        return renderer.pdfData { ctx in
            ctx.beginPage()
            var cursorY = topMargin
            cursorY = drawHeader(context: context, top: cursorY)
            cursorY = drawSummary(context: context, top: cursorY + 16)
            cursorY = drawTableHeader(top: cursorY + 16)
            cursorY = drawTable(
                entries: context.entries,
                top: cursorY,
                ctx: ctx,
                bounds: bounds
            )
            drawFooter(bottom: bounds.maxY - 24)
        }
    }

    // MARK: Sections

    private static func drawHeader(context: Context, top: CGFloat) -> CGFloat {
        let title = "Care minutes timesheet"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: UIColor.label,
        ]
        title.draw(at: CGPoint(x: horizontalMargin, y: top), withAttributes: titleAttrs)
        var lineY = top + 30

        let body: [String] = [
            "Circle: \(context.circleName)",
            context.recipientName.map { "Care recipient: \($0)" } ?? "",
            "Caregiver: \(context.caregiverDisplayName)",
            context.fiscalIntermediary.map { "Fiscal intermediary: \($0)" } ?? "",
            "Week: \(formattedRange(context.weekRange))",
            "Generated: \(Date.now.formatted(date: .abbreviated, time: .shortened))",
        ].filter { !$0.isEmpty }

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        for line in body {
            line.draw(at: CGPoint(x: horizontalMargin, y: lineY), withAttributes: bodyAttrs)
            lineY += 14
        }
        return lineY
    }

    private static func drawSummary(context: Context, top: CGFloat) -> CGFloat {
        let totalMinutes = CareMinuteService.totalMinutes(in: context.entries)
        let totalHours = Double(totalMinutes) / 60.0
        let summary = String(
            format: "Total hours this week: %.2f  (%d entries)",
            totalHours,
            context.entries.count
        )
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor.label,
        ]
        summary.draw(at: CGPoint(x: horizontalMargin, y: top), withAttributes: attrs)
        return top + 20
    }

    private static func drawTableHeader(top: CGFloat) -> CGFloat {
        let columns = ["Date", "Start", "End", "Hours", "Service code", "Notes"]
        let widths = columnWidths()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor.label,
        ]
        var xCursor = horizontalMargin
        for (column, width) in zip(columns, widths) {
            column.draw(at: CGPoint(x: xCursor, y: top), withAttributes: attrs)
            xCursor += width
        }
        let dividerY = top + 14
        UIColor.darkGray.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: horizontalMargin, y: dividerY))
        path.addLine(to: CGPoint(x: pageSize.width - horizontalMargin, y: dividerY))
        path.lineWidth = 0.5
        path.stroke()
        return dividerY + 6
    }

    private static func drawTable(
        entries: [CareMinuteEntry],
        top: CGFloat,
        ctx: UIGraphicsPDFRendererContext,
        bounds: CGRect
    )
        -> CGFloat
    {
        let widths = columnWidths()
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.label,
        ]
        var rowY = top
        let rowHeight: CGFloat = 16
        let bottomLimit = bounds.maxY - 60

        for entry in entries {
            if rowY + rowHeight > bottomLimit {
                ctx.beginPage()
                rowY = topMargin
            }
            let values = rowValues(for: entry)
            var xCursor = horizontalMargin
            for (text, width) in zip(values, widths) {
                let rect = CGRect(x: xCursor, y: rowY, width: width - 4, height: rowHeight)
                text.draw(in: rect, withAttributes: bodyAttrs)
                xCursor += width
            }
            rowY += rowHeight
        }
        return rowY
    }

    private static func drawFooter(bottom: CGFloat) {
        let disclaimer = """
        This export is provided as a ready-to-edit timesheet template. \
        It is not a direct submission to any fiscal intermediary — \
        verify against your FI's specific requirements before submitting.
        """
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let rect = CGRect(
            x: horizontalMargin,
            y: bottom,
            width: pageSize.width - (horizontalMargin * 2),
            height: 36
        )
        disclaimer.draw(in: rect, withAttributes: attrs)
    }

    // MARK: Helpers

    private static func columnWidths() -> [CGFloat] {
        let usable = pageSize.width - (horizontalMargin * 2)
        return [
            usable * 0.13,
            usable * 0.11,
            usable * 0.11,
            usable * 0.09,
            usable * 0.22,
            usable * 0.34,
        ]
    }

    private static func rowValues(for entry: CareMinuteEntry) -> [String] {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE M/d"
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let hours = String(format: "%.2f", entry.durationHours)
        let code = "\(entry.serviceCode.rawValue) · \(entry.serviceCode.displayName)"
        return [
            dayFormatter.string(from: entry.startedAt),
            timeFormatter.string(from: entry.startedAt),
            timeFormatter.string(from: entry.endedAt),
            hours,
            code,
            entry.notes ?? "",
        ]
    }

    private static func formattedRange(_ range: Range<Date>) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let end = Calendar.current.date(byAdding: .second, value: -1, to: range.upperBound)
            ?? range.upperBound
        return "\(formatter.string(from: range.lowerBound)) – \(formatter.string(from: end))"
    }
}
