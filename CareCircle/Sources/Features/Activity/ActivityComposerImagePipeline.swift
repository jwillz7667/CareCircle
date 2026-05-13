import Foundation
import UIKit

// MARK: - ActivityComposerImagePipeline

/// Compresses an image picked by the user so the resulting `Data` is small enough for
/// CloudKit asset storage and quick to thumbnail in the feed.
///
/// The pipeline targets ~1500 px on the long edge at JPEG quality 0.85, which produces files
/// comfortably under 1 MB for typical iPhone photos.
enum ActivityComposerImagePipeline {
    static let maxDimension: CGFloat = 1_500
    static let jpegQuality: CGFloat = 0.85

    static func encode(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let resized = resizeIfNeeded(image)
        return resized.jpegData(compressionQuality: jpegQuality)
    }

    private static func resizeIfNeeded(_ image: UIImage) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxDimension else { return image }

        let scale = maxDimension / longEdge
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
