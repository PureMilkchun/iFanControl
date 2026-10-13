import AppKit

@MainActor
final class UpdateProgressWindowController: NSWindowController, NSWindowDelegate {
    private let titleField = NSTextField(labelWithString: "")
    private let symbolView = NSImageView()
    private let detailField = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private let amountField = NSTextField(labelWithString: "")
    private let primaryButton = NSButton()
    private let secondaryButton = NSButton()
    private var primaryAction: (() -> Void)?
    private var secondaryAction: (() -> Void)?
    private var cancelAction: (() -> Void)?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = Self.text("软件更新", "Software Update")
        window.center()
        super.init(window: window)
        window.delegate = self
        titleField.font = .systemFont(ofSize: 16, weight: .semibold)
        detailField.font = .systemFont(ofSize: 12)
        detailField.textColor = .secondaryLabelColor
        amountField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        amountField.textColor = .secondaryLabelColor
        progress.style = .bar
        progress.minValue = 0; progress.maxValue = 1
        primaryButton.bezelStyle = .rounded
        primaryButton.target = self; primaryButton.action = #selector(primary)
        secondaryButton.bezelStyle = .rounded
        secondaryButton.target = self; secondaryButton.action = #selector(secondary)
        primaryButton.font = .systemFont(ofSize: 13)
        secondaryButton.font = .systemFont(ofSize: 12)
        let buttons = NSStackView(views: [secondaryButton, NSView(), primaryButton])
        buttons.spacing = 10
        let header = NSStackView(views: [symbolView, titleField]); header.spacing = 10
        symbolView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        symbolView.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let stack = NSStackView(views: [header, detailField, progress, amountField, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -20),
            detailField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progress.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static let language = UserDefaults.standard.string(forKey: "ifancontrol.ui.language") ?? (Locale.preferredLanguages.first?.hasPrefix("en") == true ? "en" : "zh")
    private static func text(_ zh: String, _ en: String) -> String { language == "en" ? en : zh }

    func present(title: String, detail: String, cancel: (() -> Void)? = nil,
                 retry: (() -> Void)? = nil, manual: (() -> Void)? = nil) {
        titleField.stringValue = title; detailField.stringValue = detail
        symbolView.image = NSImage(systemSymbolName: retry == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.circle", accessibilityDescription: nil)
        symbolView.contentTintColor = retry == nil ? .secondaryLabelColor : .systemOrange
        cancelAction = cancel
        primaryAction = retry ?? cancel ?? { [weak self] in self?.dismiss() }
        secondaryAction = manual
        primaryButton.title = retry != nil ? Self.text("重试", "Try Again") :
            (cancel != nil ? Self.text("取消", "Cancel") : Self.text("完成", "Done"))
        primaryButton.keyEquivalent = cancel != nil ? "\u{1b}" : "\r"
        secondaryButton.title = Self.text("手动下载", "Download Manually")
        secondaryButton.isHidden = manual == nil
        progress.isHidden = cancel == nil
        amountField.stringValue = ""
        amountField.isHidden = true
        progress.isIndeterminate = true
        if cancel != nil { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        window?.setContentSize(NSSize(width: 420, height: cancel == nil ? 170 : 190))
        bringForward()
    }

    func updateTransfer(received: Int64, total: Int64) {
        amountField.isHidden = false
        progress.isIndeterminate = total <= 0 || received > total
        if total > 0 && received <= total {
            progress.stopAnimation(nil)
            progress.doubleValue = min(1, Double(received) / Double(total))
            amountField.stringValue = "\(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
        } else {
            progress.startAnimation(nil)
            amountField.stringValue = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
        }
    }
    func bringForward() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func dismiss() { progress.stopAnimation(nil); cancelAction = nil; window?.orderOut(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancelAction?(); cancelAction = nil; return true }
    @objc private func primary() { primaryAction?() }
    @objc private func secondary() { secondaryAction?() }
}
