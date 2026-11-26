import AppKit

/// A status menu does not normally activate its owner. Native embedded controls
/// need that active context to use the user's accent instead of inactive gray.
@MainActor final class MenuActivation: NSObject, NSMenuDelegate {
    private var previousApplication: NSRunningApplication?
    private var isMenuOpen = false

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        guard !NSApp.isActive else { return }
        previousApplication = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        guard let previous = previousApplication else { return }
        previousApplication = nil
        // Menu actions run after dismissal. Let a requested app window become
        // key before deciding whether this interaction should return focus.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isMenuOpen, NSApp.isActive,
                  NSApp.keyWindow == nil, !previous.isTerminated,
                  previous != NSRunningApplication.current else { return }
            if #available(macOS 14.0, *) { NSApp.yieldActivation(to: previous) }
            previous.activate(options: [])
        }
    }
}
