import Foundation
import OSLog

// MARK: - OpenFDAClient

/// Thin URLSession wrapper around the openFDA `/drug/label.json` endpoint. No
/// API key required for low-volume reads. Used only for confirming active
/// ingredients on the AddMedication form — never for medical decision making.
struct OpenFDAClient: Sendable {
    enum LookupError: LocalizedError, Equatable, Sendable {
        case invalidURL
        case transport(String)
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Couldn't form a request for that medication name."
            case let .transport(message): message
            case let .httpStatus(code): "openFDA responded with status \(code)."
            }
        }
    }

    var session: URLSession
    var endpoint: URL

    init(
        session: URLSession = .shared,
        endpoint: URL = Self.defaultEndpoint
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    private static let defaultEndpoint: URL = {
        guard let url = URL(string: "https://api.fda.gov/drug/label.json") else {
            preconditionFailure("Hardcoded openFDA endpoint URL is invalid.")
        }
        return url
    }()

    private static let ndcEndpoint: URL = {
        guard let url = URL(string: "https://api.fda.gov/drug/ndc.json") else {
            preconditionFailure("Hardcoded openFDA NDC endpoint URL is invalid.")
        }
        return url
    }()

    /// Looks the medication up by its NDC product code (e.g. "12345-6789").
    /// Returns nil when openFDA responds with HTTP 404 or an empty results
    /// array — both are normal for unmapped/over-the-counter codes.
    func lookup(ndc: String) async throws -> OpenFDANDCResult? {
        let trimmed = ndc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard var components = URLComponents(url: Self.ndcEndpoint, resolvingAgainstBaseURL: false) else {
            throw LookupError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "search", value: "product_ndc:\"\(trimmed)\""),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components.url else { throw LookupError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 12

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LookupError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { return nil }
            guard (200 ..< 300).contains(http.statusCode) else {
                throw LookupError.httpStatus(http.statusCode)
            }
        }

        do {
            let decoded = try JSONDecoder().decode(OpenFDANDCResponse.self, from: data)
            return decoded.firstResult()
        } catch {
            AppLogger.app.error(
                "openFDA NDC decode failed: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    func lookup(name: String) async throws -> OpenFDALabelResult? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let escaped = escapeForSearch(trimmed)
        let query = """
        (openfda.brand_name:"\(escaped)" OR openfda.generic_name:"\(escaped)" OR openfda.substance_name:"\(escaped)")
        """
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw LookupError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components.url else { throw LookupError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 12

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LookupError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { return nil }
            guard (200 ..< 300).contains(http.statusCode) else {
                throw LookupError.httpStatus(http.statusCode)
            }
        }

        do {
            let decoded = try JSONDecoder().decode(OpenFDALabelResponse.self, from: data)
            return decoded.firstResult()
        } catch {
            AppLogger.app.error(
                "openFDA decode failed: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    private func escapeForSearch(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - OpenFDALabelResponse

private struct OpenFDALabelResponse: Decodable {
    var results: [Entry]?

    struct Entry: Decodable {
        var openfda: OpenFDABlock?
        var activeIngredient: [String]?

        enum CodingKeys: String, CodingKey {
            case openfda
            case activeIngredient = "active_ingredient"
        }
    }

    struct OpenFDABlock: Decodable {
        var brandName: [String]?
        var genericName: [String]?
        var substanceName: [String]?

        enum CodingKeys: String, CodingKey {
            case brandName = "brand_name"
            case genericName = "generic_name"
            case substanceName = "substance_name"
        }
    }

    func firstResult() -> OpenFDALabelResult? {
        guard let entry = results?.first else { return nil }
        let brand = (entry.openfda?.brandName ?? []).map { $0.titlecased() }
        let generic = (entry.openfda?.genericName ?? []).map { $0.titlecased() }
        let substances = (entry.openfda?.substanceName ?? []).map { $0.titlecased() }
        let activeFromLabel = (entry.activeIngredient ?? [])
            .flatMap { extractIngredients(from: $0) }
        let merged = Array(NSOrderedSet(array: substances + activeFromLabel)) as? [String] ?? []
        return OpenFDALabelResult(
            brandNames: dedup(brand),
            genericNames: dedup(generic),
            activeIngredients: merged
        )
    }
}

private func dedup(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in values where !value.isEmpty {
        let key = value.lowercased()
        if !seen.contains(key) {
            seen.insert(key)
            out.append(value)
        }
    }
    return out
}

private func extractIngredients(from sentence: String) -> [String] {
    let cleaned = sentence
        .replacingOccurrences(of: "Active ingredient:", with: "", options: .caseInsensitive)
        .replacingOccurrences(of: "Active ingredients:", with: "", options: .caseInsensitive)
    let parts = cleaned.split(whereSeparator: { ",;\n".contains($0) })
    return parts
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).titlecased() }
        .filter { !$0.isEmpty }
}

private extension String {
    func titlecased() -> String {
        let lower = lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}

// MARK: - OpenFDANDCResponse

private struct OpenFDANDCResponse: Decodable {
    var results: [Entry]?

    struct Entry: Decodable {
        var productNDC: String?
        var brandName: String?
        var genericName: String?
        var dosageForm: String?
        var route: [String]?
        var activeIngredients: [ActiveIngredient]?

        enum CodingKeys: String, CodingKey {
            case productNDC = "product_ndc"
            case brandName = "brand_name"
            case genericName = "generic_name"
            case dosageForm = "dosage_form"
            case route
            case activeIngredients = "active_ingredients"
        }
    }

    struct ActiveIngredient: Decodable {
        var name: String?
        var strength: String?
    }

    func firstResult() -> OpenFDANDCResult? {
        guard let entry = results?.first else { return nil }
        let brand = entry.brandName.map { [$0.titlecased()] } ?? []
        let generic = entry.genericName.map { [$0.titlecased()] } ?? []
        let ingredients = (entry.activeIngredients ?? [])
            .compactMap(\.name)
            .map { $0.titlecased() }
        return OpenFDANDCResult(
            productNDC: entry.productNDC ?? "",
            brandNames: dedup(brand),
            genericNames: dedup(generic),
            activeIngredients: dedup(ingredients),
            routes: entry.route ?? [],
            dosageForms: entry.dosageForm.map { [$0] } ?? []
        )
    }
}
