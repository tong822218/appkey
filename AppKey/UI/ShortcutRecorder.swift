import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: Shortcut?
    let isRecording: Bool
    let onBegin: () -> Void
    let onCommit: (Shortcut?) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        configure(view)
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        configure(view)
        if isRecording, view.window?.firstResponder !== view {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }
    }

    private func configure(_ view: ShortcutRecorderView) {
        view.shortcut = shortcut
        view.isRecording = isRecording
        view.onBegin = onBegin
        view.onCommit = onCommit
        view.onCancel = onCancel
        view.needsDisplay = true
    }
}

final class ShortcutRecorderView: NSView {
    var shortcut: Shortcut?
    var isRecording = false
    var onBegin: (() -> Void)?
    var onCommit: ((Shortcut?) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 132, height: 28) }

    override func mouseDown(with event: NSEvent) {
        onBegin?()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            onCommit?(nil)
            return
        }

        let modifiers = ShortcutModifiers(event.modifierFlags)
        guard let shortcut = Shortcut.make(keyCode: UInt32(event.keyCode), modifiers: modifiers) else {
            NSSound.beep()
            return
        }
        onCommit?(shortcut)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text = isRecording ? "请按快捷键…" : (shortcut?.displayText ?? "点击录制")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: shortcut == nil ? .regular : .medium),
            .foregroundColor: shortcut == nil ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }
}

private extension ShortcutModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var value: ShortcutModifiers = []
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.shift) { value.insert(.shift) }
        self = value
    }
}
