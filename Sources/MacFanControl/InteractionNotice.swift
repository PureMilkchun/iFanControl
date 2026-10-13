import AppKit

@MainActor private final class CompletionMarkView: NSView {
    static let size: CGFloat = 36
    private let check = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let ring = CAShapeLayer()
        ring.frame = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        ring.path = CGPath(ellipseIn: CGRect(x: 1.5, y: 1.5, width: 33, height: 33), transform: nil)
        ring.fillColor = NSColor.systemGreen.withAlphaComponent(0.1).cgColor
        ring.strokeColor = NSColor.systemGreen.cgColor; ring.lineWidth = 2
        layer?.addSublayer(ring)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 9.75, y: 18)); path.addLine(to: CGPoint(x: 15.3, y: 12.75)); path.addLine(to: CGPoint(x: 26.25, y: 23.55))
        check.path = path; check.fillColor = nil; check.strokeColor = NSColor.systemGreen.cgColor
        check.frame = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        check.lineWidth = 3; check.lineCap = .round; check.lineJoin = .round
        layer?.addSublayer(check)
        setAccessibilityElement(true); setAccessibilityLabel("✓")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func animate() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let reveal = CABasicAnimation(keyPath: "strokeEnd")
        reveal.fromValue = 0; reveal.toValue = 1; reveal.duration = 0.24
        reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
        check.add(reveal, forKey: "completion")
    }
}

/// One rounded fill owns the entire surface. Popover material adds its own bright
/// edge on some appearances, so this brief acknowledgement uses a system-color
/// surface with transparent corners and the native window shadow instead.
@MainActor private final class NoticeBackgroundView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// A short, non-modal acknowledgement, emitted only after the corresponding operation succeeds.
@MainActor final class InteractionNotice {
    static let shared = InteractionNotice()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ message: String, symbol: String = "checkmark.circle.fill") {
        hideWork?.cancel(); panel?.orderOut(nil)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 80),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true
        let surface = NoticeBackgroundView(frame: panel.contentView!.bounds)
        let icon: NSView
        if symbol.hasPrefix("checkmark") { icon = CompletionMarkView(frame: .zero) }
        else {
            let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
            image.contentTintColor = .controlAccentColor; icon = image
        }
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        let row = NSStackView(views: [icon, label]); row.spacing = 12; row.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(row); panel.contentView = surface
        let iconSize: CGFloat = icon is CompletionMarkView ? CompletionMarkView.size : 24
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: iconSize), icon.heightAnchor.constraint(equalToConstant: iconSize),
            row.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),
            row.centerYAnchor.constraint(equalTo: surface.centerYAnchor)
        ])
        panel.center(); panel.orderFrontRegardless(); self.panel = panel
        (icon as? CompletionMarkView)?.animate()
        NSAccessibility.post(element: label, notification: .announcementRequested, userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        let work = DispatchWorkItem { [weak panel] in
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { panel?.orderOut(nil) }
            else { NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel?.animator().alphaValue = 0 }, completionHandler: { [weak panel] in Task { @MainActor in panel?.orderOut(nil) } }) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
}
