import AppKit

/// A shared scale for this menu-bar utility. Navigation inherits native materials;
/// content uses quiet system colors and compact, readable controls.
@MainActor enum NativeInterface {
    static func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor, wrapping: Bool = false) -> NSTextField {
        let field = wrapping ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    static func button(_ text: String, target: AnyObject?, action: Selector?, small: Bool = false) -> NSButton {
        let button = NSButton(title: text, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = small ? .small : .regular
        button.font = .systemFont(ofSize: small ? 12 : 13)
        return button
    }

    static func rpm(_ value: Int) -> NSAttributedString {
        measurement("\(value)", unit: "RPM")
    }

    static func measurement(_ value: String, unit: String) -> NSAttributedString {
        let text = NSMutableAttributedString(string: value, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 34, weight: .medium), .foregroundColor: NSColor.labelColor
        ])
        text.append(NSAttributedString(string: " " + unit, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor
        ]))
        return text
    }
}
