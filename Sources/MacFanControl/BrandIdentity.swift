import AppKit

/// Approved Soft Cast outlines. Template PDFs keep the geometry intact while
/// the native label color follows the window's light or dark appearance.
@MainActor enum BrandIdentity {
    enum Wordmark: String {
        case horizontal = "WordmarkHorizontal"
        case stacked = "WordmarkStacked"
    }

    static func wordmark(_ style: Wordmark, width: CGFloat) -> NSView {
        guard let image = image(for: style) else {
            return NativeInterface.label("iFanControl", size: 17, weight: .semibold)
        }
        image.isTemplate = true
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.contentTintColor = .labelColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.identifier = NSUserInterfaceItemIdentifier("brand-wordmark-\(style.rawValue)")
        view.setAccessibilityElement(true)
        view.setAccessibilityLabel("iFanControl")
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: width * image.size.height / image.size.width)
        ])
        return view
    }

    /// AppKit's application icon includes system padding. Match the opaque artwork,
    /// not the image-view frames, so installed and preview Apps share the same edges.
    static func wordmark(_ style: Wordmark, matching icon: NSImageView, iconSize: CGFloat) -> NSView {
        guard let mark = image(for: style), icon.image != nil else {
            return wordmark(style, width: iconSize * 2)
        }
        let iconInk = visibleBounds(of: icon, size: iconSize)
        let markInk = inkBounds(mark, at: mark.size, pdfURL: url(for: style))
        let height = iconInk.height * iconSize / markInk.height
        let width = height * mark.size.width / mark.size.height
        let artwork = wordmark(style, width: width)
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(artwork)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: width),
            container.heightAnchor.constraint(equalToConstant: iconSize),
            artwork.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            // A negative bottom-anchor offset raises the artwork in AppKit.
            artwork.bottomAnchor.constraint(equalTo: container.bottomAnchor,
                constant: markInk.minY * height - iconInk.minY * iconSize)
        ])
        return container
    }

    private static func visibleBounds(of view: NSImageView, size: CGFloat) -> NSRect {
        view.setFrameSize(NSSize(width: size, height: size))
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return NSRect(x: 0, y: 0, width: 1, height: 1)
        }
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var minY = bitmap.pixelsHigh, maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= 0.25 {
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxY >= minY else { return NSRect(x: 0, y: 0, width: 1, height: 1) }
        return NSRect(x: 0, y: CGFloat(bitmap.pixelsHigh - maxY - 1) / CGFloat(bitmap.pixelsHigh), width: 1,
                      height: CGFloat(maxY - minY + 1) / CGFloat(bitmap.pixelsHigh))
    }

    private static func image(for style: Wordmark) -> NSImage? {
        guard let url = url(for: style) else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func url(for style: Wordmark) -> URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource: style.rawValue, withExtension: "pdf", subdirectory: "Brand")
    }

    /// Normalized visible bounds, in AppKit's bottom-left coordinate system.
    /// Ignore the faint system shadow when identifying the icon's body.
    private static func inkBounds(_ image: NSImage, at size: NSSize, pdfURL: URL? = nil) -> NSRect {
        let width = max(1, Int(ceil(size.width * 2)))
        let height = max(1, Int(ceil(size.height * 2)))
        let full = NSRect(x: 0, y: 0, width: 1, height: 1)
        var proposed = NSRect(origin: .zero, size: size)
        let page = pdfURL.flatMap { CGPDFDocument($0 as CFURL)?.page(at: 1) }
        let source = page == nil ? image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) : nil
        guard page != nil || source != nil else { return full }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        let measured = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            if let page {
                let box = page.getBoxRect(.mediaBox)
                context.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
                context.translateBy(x: -box.minX, y: -box.minY)
                context.drawPDFPage(page)
            } else if let source {
                context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            let bytes = buffer.bindMemory(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width where bytes[(y * width + x) * 4 + 3] >= 64 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            return true
        }
        guard measured else { return full }
        guard maxX >= minX, maxY >= minY else { return full }
        return NSRect(x: CGFloat(minX) / CGFloat(width), y: CGFloat(height - maxY - 1) / CGFloat(height),
                      width: CGFloat(maxX - minX + 1) / CGFloat(width), height: CGFloat(maxY - minY + 1) / CGFloat(height))
    }
}
