// MacThumbnailCache.swift — bounded, downsampled thumbnails for stored recipe photos.
//
// A recipe row used to call `NSImage(data:)` on the full stored photo every time SwiftUI
// re-evaluated the row body. With hundreds of visible/scrolling rows that decodes the same
// full-size JPEG repeatedly on the main thread. This cache decodes each photo once, at the
// size the row actually draws, and keeps the result in a byte-bounded NSCache that the system
// may also purge under memory pressure. It never touches disk and never owns recipe data.

import AppKit
import ImageIO

@MainActor
final class MacThumbnailCache {
    static let shared = MacThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 600
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    /// A thumbnail no larger than `maxPixel` on its long edge, or nil when the bytes are not a
    /// decodable image. The key includes the byte count so a replaced photo is not served stale.
    func thumbnail(id: UUID, data: Data, maxPixel: Int) -> NSImage? {
        let bounded = min(max(maxPixel, 32), 1_024)
        let key = "\(id.uuidString)|\(data.count)|\(bounded)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: bounded,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key, cost: max(1, cgImage.bytesPerRow * cgImage.height))
        return image
    }

    func removeAll() { cache.removeAllObjects() }
}
