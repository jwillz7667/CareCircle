import Foundation
import OSLog
import PhotosUI
import SwiftUI

// MARK: - DocumentCandidate

/// Validated plaintext bytes ready for encryption. Wraps the file payload
/// with the MIME type and original filename detected during import. The
/// view layer asks the pipeline for a candidate; the pipeline does header
/// sniffing and size enforcement so `AddDocumentView` can stay declarative.
struct DocumentCandidate: Equatable {
    let data: Data
    let mimeType: String
    let filename: String
}

// MARK: - DocumentCandidateError

enum DocumentCandidateError: LocalizedError {
    case unsupportedType
    case oversized
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            "That file type isn't supported. Pick a JPG, PNG, HEIC, or PDF."
        case .oversized:
            "That file is over 10 MB. Compress it or scan at a lower resolution."
        case let .unreadable(message):
            message
        }
    }
}

// MARK: - DocumentCandidatePipeline

enum DocumentCandidatePipeline {
    static func loadPhoto(_ item: PhotosPickerItem) async throws -> DocumentCandidate {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw DocumentCandidateError.unreadable("Couldn't read the selected photo.")
            }
            let mime = detectImageMime(in: data)
            return try validated(
                data: data,
                mimeType: mime,
                filename: "photo.\(mime.split(separator: "/").last ?? "jpg")"
            )
        } catch let error as DocumentCandidateError {
            throw error
        } catch {
            AppLogger.persistence.error(
                "Photo load failed: \(String(describing: error), privacy: .public)"
            )
            throw DocumentCandidateError.unreadable("Couldn't read the selected photo.")
        }
    }

    static func loadPDF(from url: URL) throws -> DocumentCandidate {
        let shouldStop = url.startAccessingSecurityScopedResource()
        defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            return try validated(data: data, mimeType: "application/pdf", filename: url.lastPathComponent)
        } catch let error as DocumentCandidateError {
            throw error
        } catch {
            AppLogger.persistence.error(
                "PDF read failed: \(String(describing: error), privacy: .public)"
            )
            throw DocumentCandidateError.unreadable("Couldn't read that PDF.")
        }
    }

    private static func validated(
        data: Data,
        mimeType: String,
        filename: String
    ) throws
        -> DocumentCandidate
    {
        guard DocumentDraft.allowedMimeTypes.contains(mimeType) else {
            throw DocumentCandidateError.unsupportedType
        }
        guard data.count <= DocumentDraft.maxSizeBytes else {
            throw DocumentCandidateError.oversized
        }
        return DocumentCandidate(data: data, mimeType: mimeType, filename: filename)
    }

    private static func detectImageMime(in data: Data) -> String {
        guard let first = data.first else { return "image/jpeg" }
        switch first {
        case 0x89: return "image/png"
        case 0xFF: return "image/jpeg"
        default: return "image/heic"
        }
    }
}
