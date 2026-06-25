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

/// Crop a CGImage to a Vision normalized bounding box (origin bottom-left, range 0-1).
/// Returns nil if the resulting crop would be empty or out of bounds.
func cropCGImage(_ image: CGImage, to normalizedRect: CGRect) -> CGImage? {
    let imgWidth = CGFloat(image.width)
    let imgHeight = CGFloat(image.height)

    // Vision coords (bottom-left origin) → CGImage pixel coords (top-left origin)
    let pixelX = normalizedRect.origin.x * imgWidth
    let pixelY = (1.0 - normalizedRect.origin.y - normalizedRect.size.height) * imgHeight
    let pixelWidth = normalizedRect.size.width * imgWidth
    let pixelHeight = normalizedRect.size.height * imgHeight

    let pixelRect = CGRect(x: pixelX, y: pixelY, width: pixelWidth, height: pixelHeight)
    let clamped = pixelRect.integral.intersection(
        CGRect(x: 0, y: 0, width: imgWidth, height: imgHeight)
    )
    guard clamped.width > 0, clamped.height > 0 else { return nil }
    return image.cropping(to: clamped)
}
