import AppKit

@MainActor private final class StartupSurfaceView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Launch feedback stays visible until the existing initialization returns.
/// Native threaded animation keeps the indicator moving during synchronous probes.
@MainActor final class StartupProgressWindowController: NSWindowController {
    enum Stage {
        case hardware, preferences, controls

        @MainActor var message: String {
            switch self {
            case .hardware: return StartupProgressWindowController.text("正在识别温度与风扇…", "Detecting temperatures and fans…")
            case .preferences: return StartupProgressWindowController.text("正在恢复你的设置…", "Restoring your settings…")
            case .controls: return StartupProgressWindowController.text("正在准备菜单栏与风扇控制…", "Preparing menu bar and fan control…")
            }
        }
    }

    private let stageField = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 156),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.setAccessibilityLabel(Self.text("iFanControl 正在启动", "Starting iFanControl"))
        super.init(window: panel)

        let surface = StartupSurfaceView(frame: panel.contentView!.bounds)
        panel.contentView = surface
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let title = NativeInterface.label(Self.text("正在启动 iFanControl", "Starting iFanControl"), size: 17, weight: .semibold)
        stageField.font = .systemFont(ofSize: 12)
        stageField.textColor = .secondaryLabelColor
        stageField.identifier = NSUserInterfaceItemIdentifier("startup-stage")
        let text = NSStackView(views: [title, stageField])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 6
        let header = NSStackView(views: [icon, text])
        header.alignment = .centerY
        header.spacing = 16

        progress.style = .spinning
        progress.controlSize = .small
        progress.isIndeterminate = true
        progress.usesThreadedAnimation = true
        progress.setAccessibilityLabel(Self.text("正在启动", "Starting"))
        progress.widthAnchor.constraint(equalToConstant: 16).isActive = true
        progress.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let hint = NativeInterface.label(Self.text("准备完成后，可在菜单栏使用。", "Available in your menu bar when ready."), size: 12, color: .secondaryLabelColor)
        let footer = NSStackView(views: [progress, hint])
        footer.alignment = .centerY
        footer.spacing = 8
        let stack = NSStackView(views: [header, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stageField.widthAnchor.constraint(equalTo: text.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func text(_ zh: String, _ en: String) -> String {
        let language = UserDefaults.standard.string(forKey: "ifancontrol.ui.language")
            ?? (Locale.preferredLanguages.first?.hasPrefix("en") == true ? "en" : "zh")
        return language == "en" ? en : zh
    }

    func present() {
        setStage(.hardware)
        window?.center()
        window?.orderFrontRegardless()
        progress.startAnimation(nil)
        window?.displayIfNeeded()
        NSAccessibility.post(element: stageField, notification: .announcementRequested,
                             userInfo: [.announcement: Self.text("iFanControl 正在启动", "Starting iFanControl"),
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    func setStage(_ stage: Stage) {
        stageField.stringValue = stage.message
        // Flush the label before entering the existing synchronous startup step.
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.contentView?.needsDisplay = true
        window?.displayIfNeeded()
    }

    func dismiss() {
        progress.stopAnimation(nil)
        window?.orderOut(nil)
    }
}
