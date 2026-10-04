import AppKit
import Foundation

// A sidebar background stays visible on the native success page. A custom
// conclusion would hide Installer's own success indicator.
guard CommandLine.arguments.count == 2 else { fatalError("Usage: render_open_hint output-directory") }
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let size = NSSize(width: 176, height: 218)
final class OpenHintView: NSView {
    var dark = false
    override func draw(_ dirtyRect: NSRect) {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 3
    let first = NSAttributedString(string: "安装完成后，从\n「应用程序」打开\niFanControl。", attributes: [
        .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
        .foregroundColor: NSColor(white: dark ? 0.88 : 0.20, alpha: 1),
        .paragraphStyle: style
    ])
    first.draw(in: NSRect(x: 20, y: 143, width: 144, height: 60))
    let second = NSAttributedString(string: "若系统阻止打开，\n前往「系统设置」→\n「隐私与安全性」，\n点「仍要打开」，\n再确认「打开」。", attributes: [
        .font: NSFont.systemFont(ofSize: 10.5),
        .foregroundColor: NSColor(white: dark ? 0.70 : 0.38, alpha: 1),
        .paragraphStyle: style
    ])
    second.draw(in: NSRect(x: 20, y: 52, width: 144, height: 85))
    }
}
for dark in [false, true] {
    let view = OpenHintView(frame: NSRect(origin: .zero, size: size))
    view.dark = dark
    let data = view.dataWithPDF(inside: view.bounds)
    try data.write(to: output.appendingPathComponent(dark ? "OpenHint-dark.pdf" : "OpenHint.pdf"))
}
