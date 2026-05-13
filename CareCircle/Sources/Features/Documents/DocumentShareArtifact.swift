import Foundation
import OSLog
import UniformTypeIdentifiers

// MARK: - DocumentShareArtifact

/// Writes decrypted document bytes to a short-lived file in the app's
/// `tmp/carecircle-share` directory so `ShareLink` has a URL to hand to
/// the system share sheet. The caller is responsible for invoking
/// `remove(at:)` on dismiss to keep plaintext copies from lingering.
enum DocumentShareArtifact {
    private static let folderName = "carecircle-share"

    static func write(_ data: Data, suggestedFilename: String, mimeType: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = sanitizedFilename(from: suggestedFilename, mimeType: mimeType)
        let url = directory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: .completeFileProtection)
        return url
    }

    static func remove(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func sanitizedFilename(from raw: String, mimeType: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "document" : trimmed
        let cleaned = base.replacingOccurrences(
            of: "[^A-Za-z0-9._-]+",
            with: "_",
            options: .regularExpression
        )
        let ext = preferredExtension(for: mimeType)
        return cleaned.lowercased().hasSuffix(".\(ext)") ? cleaned : "\(cleaned).\(ext)"
    }

    private static func preferredExtension(for mimeType: String) -> String {
        if let type = UTType(mimeType: mimeType), let ext = type.preferredFilenameExtension {
            return ext
        }
        switch mimeType {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "application/pdf": return "pdf"
        default: return "bin"
        }
    }
}
