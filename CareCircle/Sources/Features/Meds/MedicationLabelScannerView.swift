import OSLog
import SwiftUI
import VisionKit

// MARK: - MedicationLabelScannerView

/// VisionKit-backed sheet that recognizes printed text on a medication label,
/// previews the captured lines, and returns a parsed suggestion via the
/// `onSuggestion` callback when the user confirms.
struct MedicationLabelScannerView: View {
    let onSuggestion: (MedicationLabelSuggestion) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recognizedLines: [String] = []
    @State private var availability: ScannerAvailability = .unknown

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch availability {
                case .unknown, .checking:
                    progressView
                case .ready:
                    scannerLayer
                case let .unsupported(message):
                    unavailableView(message: message)
                case let .denied(message):
                    unavailableView(message: message)
                }
            }
            .navigationTitle("Scan label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { toolbar }
            .task { await checkAvailability() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .tint(Color.white)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Use") {
                let suggestion = MedicationLabelParser().parse(lines: recognizedLines)
                if suggestion.isUseful {
                    onSuggestion(suggestion)
                }
                dismiss()
            }
            .tint(Color.white)
            .disabled(recognizedLines.isEmpty)
        }
    }

    private var progressView: some View {
        VStack(spacing: Theme.spacing) {
            ProgressView()
                .tint(.white)
            Text("Preparing camera…")
                .foregroundStyle(Color.white)
        }
    }

    private var scannerLayer: some View {
        VStack(spacing: 0) {
            DataScannerRepresentable(recognizedLines: $recognizedLines)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            recognizedPreview
        }
    }

    private var recognizedPreview: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            Text(recognizedLines.isEmpty
                ? "Hold the camera over the prescription label."
                : "Detected text")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(recognizedLines, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
        }
        .padding(Theme.spacing)
        .background(Color.black.opacity(0.6))
    }

    private func unavailableView(message: String) -> some View {
        VStack(spacing: Theme.spacing) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.white)
            Text(message)
                .font(.body)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.looseSpacing)
        }
    }

    private func checkAvailability() async {
        availability = .checking
        guard DataScannerViewController.isSupported else {
            availability = .unsupported("This device can't run the label scanner. Enter the medication manually.")
            return
        }
        guard DataScannerViewController.isAvailable else {
            availability = .denied("Camera access is required to scan labels. Enable it in Settings → CareCircle.")
            return
        }
        availability = .ready
    }
}

// MARK: - ScannerAvailability

private enum ScannerAvailability: Equatable {
    case unknown
    case checking
    case ready
    case unsupported(String)
    case denied(String)
}

// MARK: - DataScannerRepresentable

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    @Binding var recognizedLines: [String]

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        Task { @MainActor in
            do {
                try controller.startScanning()
            } catch {
                AppLogger.app.error(
                    "DataScanner start failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
        return controller
    }

    func updateUIViewController(_: DataScannerViewController, context _: Context) {}

    static func dismantleUIViewController(
        _ controller: DataScannerViewController,
        coordinator _: Coordinator
    ) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(lines: $recognizedLines)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let lines: Binding<[String]>

        init(lines: Binding<[String]>) {
            self.lines = lines
        }

        func dataScanner(
            _: DataScannerViewController,
            didAdd _: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            apply(items: allItems)
        }

        func dataScanner(
            _: DataScannerViewController,
            didRemove _: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            apply(items: allItems)
        }

        func dataScanner(
            _: DataScannerViewController,
            didUpdate _: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            apply(items: allItems)
        }

        private func apply(items: [RecognizedItem]) {
            let strings: [String] = items.compactMap { item in
                if case let .text(text) = item {
                    return text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return nil
            }
            let dedup = NSOrderedSet(array: strings).array as? [String] ?? []
            lines.wrappedValue = dedup.filter { !$0.isEmpty }
        }
    }
}
