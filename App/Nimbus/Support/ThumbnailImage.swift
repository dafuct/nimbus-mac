import SwiftUI
import AppKit
import ImageIO

/// Loads a downscaled thumbnail for a local image via ImageIO (memory-light —
/// never decodes the full-resolution image). Falls back to a tinted placeholder
/// while loading or for formats it can't read.
struct ThumbnailImage: View {
    let url: URL
    let maxPixel: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Theme.Colors.treemapTile(for: url.path))
            }
        }
        .task(id: url) {
            image = await Self.load(url, maxPixel: maxPixel)
        }
    }

    static func load(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: .zero)
        }.value
    }
}
