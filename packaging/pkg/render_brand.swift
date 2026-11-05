// Appended only to the isolated native UI fixture. Never shipped.
@MainActor enum BrandPreview {
    static func capture(directory: URL) throws {
        let language = UserDefaults.standard.string(forKey: "ifancontrol.ui.language") ?? "zh"
        let help = HelpWindowController()
        let startup = StartupProgressWindowController()
        for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            help.window?.appearance = NSAppearance(named: appearance)
            help.showWindow(nil)
            help.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try capture(help.window!, to: directory.appendingPathComponent("about-\(language)-\(theme).png"), wordmarks: 2)
            startup.window?.appearance = NSAppearance(named: appearance)
            startup.present()
            try capture(startup.window!, to: directory.appendingPathComponent("startup-\(language)-\(theme).png"), wordmarks: 1)
            startup.setStage(.preferences)
            startup.setStage(.controls)
            startup.dismiss()
        }
        help.window?.orderOut(nil)
        print("PASS: rendered real about/startup brand surfaces, light and dark / \(language)")
    }

    private static func capture(_ window: NSWindow, to url: URL, wordmarks: Int) throws {
        let view = window.contentView!
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        // Let native appearance and scroll-view drawing settle before capture.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
        func marks(_ root: NSView) -> [NSImageView] {
            let own = (root as? NSImageView).flatMap { $0.identifier?.rawValue.hasPrefix("brand-wordmark-") == true ? $0 : nil }
            return [own].compactMap { $0 } + root.subviews.flatMap { marks($0) }
        }
        let images = marks(view)
        precondition(images.count == wordmarks, "Packaged vector wordmarks must load")
        for image in images {
            precondition(image.image?.representations.first is NSPDFImageRep)
            precondition(image.accessibilityLabel() == "iFanControl")
            let rect = image.convert(image.bounds, to: view)
            precondition(view.bounds.contains(rect), "Brand mark must fit the window")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try process.run()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0, "Native window capture must succeed")
    }
}
