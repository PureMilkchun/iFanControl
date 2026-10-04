import AppKit
import Foundation

// Installer uses Cocoa rich text, not a browser. RTFD embeds the actual App
// icon and keeps native typography, spacing and alignment predictable.
let arguments = CommandLine.arguments
guard arguments.count == 4 else { fatalError("Usage: render_welcome icon.png copy.json output.rtfd") }
let iconURL = URL(fileURLWithPath: arguments[1])
let copyURL = URL(fileURLWithPath: arguments[2])
let outputURL = URL(fileURLWithPath: arguments[3])
let copy = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: copyURL))
let document = NSMutableAttributedString(string: "")

func paragraph(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
               spaceBefore: CGFloat = 0, spaceAfter: CGFloat = 0,
               color: NSColor = .textColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.paragraphSpacingBefore = spaceBefore
    style.paragraphSpacing = spaceAfter
    style.lineSpacing = 2
    document.append(NSAttributedString(string: text + "\n", attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style
    ]))
}

guard let icon = NSImage(contentsOf: iconURL) else { fatalError("Cannot load App icon") }
icon.size = NSSize(width: 64, height: 64)
let attachment = NSTextAttachment()
attachment.fileWrapper = try FileWrapper(url: iconURL, options: .immediate)
attachment.fileWrapper?.preferredFilename = "AppIcon.png"
attachment.attachmentCell = NSTextAttachmentCell(imageCell: icon)
let imageParagraph = NSMutableParagraphStyle()
imageParagraph.alignment = .center
imageParagraph.paragraphSpacingBefore = 6
imageParagraph.paragraphSpacing = 6
let iconText = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
iconText.append(NSAttributedString(string: "\n"))
iconText.addAttribute(.paragraphStyle, value: imageParagraph, range: NSRange(location: 0, length: iconText.length))
document.append(iconText)
paragraph(copy["title"]!, size: 23, weight: .semibold, spaceAfter: 4)
paragraph(copy["tagline"]!, size: 12, spaceAfter: 16)
paragraph(copy["before_install"]!, size: 13, weight: .semibold, spaceAfter: 6)
paragraph(copy["installation"]!, size: 12, spaceAfter: 18)
paragraph(copy["requirements"]!, size: 10, spaceAfter: 4, color: .secondaryLabelColor)
paragraph(copy["compatibility"]!, size: 10, color: .secondaryLabelColor)

let data = try document.data(from: NSRange(location: 0, length: document.length),
                             documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
let restored = try NSAttributedString(data: data,
                                      options: [.documentType: NSAttributedString.DocumentType.rtfd],
                                      documentAttributes: nil)
guard let restoredAttachment = restored.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment,
      restoredAttachment.fileWrapper?.regularFileContents == (try Data(contentsOf: iconURL)) else {
    fatalError("Embedded App icon differs from source")
}
let storage = NSTextStorage(attributedString: restored)
let layout = NSLayoutManager()
let container = NSTextContainer(size: NSSize(width: 400, height: 1000))
container.lineFragmentPadding = 0
storage.addLayoutManager(layout)
layout.addTextContainer(container)
layout.ensureLayout(for: container)
guard layout.usedRect(for: container).height <= 320 else {
    fatalError("Welcome content exceeds the Installer content frame")
}
try data.write(to: outputURL, options: .atomic)
