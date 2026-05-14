import OSLog
import SwiftUI
import Vision
import VisionKit

// MARK: - PillScannerView

/// Leaf scanner view used inside `PillIdentifierView`. Renders the
/// VisionKit barcode camera plus a preview bar — the coordinator owns
/// the navigation chrome (title + Cancel/Use toolbar items) so the
/// scanner can sit inline alongside the lookup/result phases without
/// nesting a second NavigationStack.
///
/// Symbology list intentionally mirrors what US prescription bottles
/// carry: UPC-A and EAN-13 for retail-printed labels, Code-128 and
/// Code-39 for pharmacy-printed labels (CVS/Walgreens use Code-128
/// extensively).
struct PillScannerView: View {
    @Binding var detectedPayload: String?

    @State private var availability: ScannerAvailability = .unknown

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch availability {
            case .unknown, .checking:
                progressView
            case .ready:
                scannerLayer
            case let .unsupported(message), let .denied(message):
                unavailableView(message: message)
            }
        }
        .task { await checkAvailability() }
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
            BarcodeScannerRepresentable(detectedPayload: $detectedPayload)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            previewBar
        }
    }

    private var previewBar: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            Text(detectedPayload == nil
                ? "Hold the camera over the bottle's barcode."
                : "Captured — tap Use to look it up.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white)
            if let detectedPayload {
                Text(detectedPayload)
                    .font(.body.monospaced())
                    .foregroundStyle(Color.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            availability = .unsupported(
                "This device can't run the barcode scanner. Enter the medication manually."
            )
            return
        }
        guard DataScannerViewController.isAvailable else {
            availability = .denied(
                "Camera access is required to scan barcodes. Enable it in Settings → CareCircle."
            )
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

// MARK: - BarcodeScannerRepresentable

private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    @Binding var detectedPayload: String?

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39]),
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
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
                    "Pill scanner start failed: \(String(describing: error), privacy: .public)"
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
        Coordinator(payload: $detectedPayload)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let payload: Binding<String?>

        init(payload: Binding<String?>) {
            self.payload = payload
        }

        func dataScanner(
            _: DataScannerViewController,
            didAdd items: [RecognizedItem],
            allItems _: [RecognizedItem]
        ) {
            apply(items: items)
        }

        func dataScanner(
            _: DataScannerViewController,
            didUpdate items: [RecognizedItem],
            allItems _: [RecognizedItem]
        ) {
            apply(items: items)
        }

        private func apply(items: [RecognizedItem]) {
            let payloadValue: String? = items.compactMap { item -> String? in
                if case let .barcode(barcode) = item {
                    return barcode.payloadStringValue
                }
                return nil
            }.first
            if let payloadValue, payload.wrappedValue != payloadValue {
                payload.wrappedValue = payloadValue
            }
        }
    }
}
