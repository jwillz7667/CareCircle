import Foundation
import OSLog

// MARK: - PillIdentifier

/// Orchestrates the UPC → NDC → openFDA lookup pipeline.
///
/// The scanner hands us an opaque payload string. We expand it into a
/// ranked list of NDC candidates via `UPCNormalizer`, then hit openFDA's
/// `/drug/ndc.json` endpoint in order. The first match wins.
///
/// The pipeline is intentionally serial. openFDA's free tier limits us to
/// 240 requests/minute and bottle scans are rare, so parallelizing three
/// candidate queries to save ~300ms would burn quota for no real win.
struct PillIdentifier: Sendable {
    var client: OpenFDAClient

    init(client: OpenFDAClient = OpenFDAClient()) {
        self.client = client
    }

    /// Looks up the scanned barcode payload. Returns nil when none of the
    /// derived NDC candidates produce an openFDA match — the UI surfaces
    /// "unknown barcode" and routes the user to the manual-entry flow.
    func identify(payload: String) async throws -> PillIdentificationResult? {
        let candidates = UPCNormalizer.candidateNDCs(from: payload)
        guard !candidates.isEmpty else { return nil }

        for candidate in candidates {
            do {
                if let record = try await client.lookup(ndc: candidate) {
                    AppLogger.app.info(
                        "Pill identifier matched NDC \(candidate, privacy: .public) for payload \(payload, privacy: .public)."
                    )
                    return PillIdentificationResult(
                        scannedPayload: payload,
                        matchedNDC: record.productNDC.isEmpty ? candidate : record.productNDC,
                        brandNames: record.brandNames,
                        genericNames: record.genericNames,
                        activeIngredients: record.activeIngredients,
                        routes: record.routes,
                        dosageForms: record.dosageForms
                    )
                }
            } catch let error as OpenFDAClient.LookupError {
                if case .httpStatus(404) = error { continue }
                throw error
            }
        }
        AppLogger.app.info(
            "Pill identifier exhausted candidates for payload \(payload, privacy: .public)."
        )
        return nil
    }
}
