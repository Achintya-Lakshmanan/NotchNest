import AppKit
import CoreImage

enum ColorExtractor {
    /// A pleasant, vibrant-ish color derived from the image's average.
    static func vibrant(from image: NSImage) -> NSColor? {
        guard let avg = average(from: image)?.usingColorSpace(.sRGB) else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        avg.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Normalize so dark or washed-out art still gives a usable tint.
        let s2 = min(max(s * 1.4, 0.45), 0.85)
        let b2 = min(max(b, 0.45), 0.68)
        return NSColor(hue: h, saturation: s2, brightness: b2, alpha: 1)
    }

    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func average(from image: NSImage) -> NSColor? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cg = bitmap.cgImage else { return nil }

        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: ci.extent),
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output,
                       toBitmap: &pixel,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        return NSColor(srgbRed: CGFloat(pixel[0]) / 255,
                       green: CGFloat(pixel[1]) / 255,
                       blue: CGFloat(pixel[2]) / 255,
                       alpha: 1)
    }
}
