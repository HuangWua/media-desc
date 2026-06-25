import CoreGraphics
import ImageIO
import AppKit

/// Load a CGImage from file path. Tries CGImageSource first; falls back to NSImage for formats
/// like WebP that CGImageSource doesn't natively support.
func loadCGImage(_ path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)

    // Path 1: CGImageSource (handles png, jpg, heic, bmp, gif)
    if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
       CGImageSourceGetCount(src) > 0,
       let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) {
        return cgImage
    }

    // Path 2: NSImage fallback (handles WebP and other formats NSImage natively supports)
    if let nsImage = NSImage(contentsOf: url),
       let tiffData = nsImage.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let cgImage = bitmap.cgImage {
        return cgImage
    }

    return nil
}
