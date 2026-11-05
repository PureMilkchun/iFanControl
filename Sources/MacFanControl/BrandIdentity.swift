import AppKit

/// Approved Soft Cast outlines. Template PDFs keep the geometry intact while
/// the native label color follows the window's light or dark appearance.
@MainActor enum BrandIdentity {
    enum Wordmark: String {
        case horizontal = "WordmarkHorizontal"
        case stacked = "WordmarkStacked"
    }

    static func wordmark(_ style: Wordmark, width: CGFloat) -> NSView {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: style.rawValue, withExtension: "pdf", subdirectory: "Brand"),
              let image = NSImage(contentsOf: url), image.size.width > 0 else {
            // Keep the product name accessible even if a third-party bundle
            // assembly omitted the artwork.
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
}
