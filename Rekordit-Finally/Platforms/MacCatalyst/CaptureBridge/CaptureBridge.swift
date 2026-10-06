import AppKit
import ScreenCaptureKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

@MainActor private var session: CaptureSession?
@MainActor private var menuBar: CaptureMenuBar?

@_cdecl("rekordit_install_menu")
public func rekorditInstallMenu(_ action: @escaping @convention(c) (Int32) -> Void) {
    DispatchQueue.main.async { if menuBar == nil { menuBar = CaptureMenuBar(action: action) } }
}

@MainActor private final class CaptureMenuBar: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let action: @convention(c) (Int32) -> Void
    var lastSaved: URL?

    init(action: @escaping @convention(c) (Int32) -> Void) {
        self.action = action
        super.init()
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        update("viewfinder", label: "Rekordit — Select Area")
    }
    func update(_ symbol: String, label: String, elapsed: String = "") {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        image?.isTemplate = symbol != "stop.circle.fill"
        item.button?.image = image
        item.button?.contentTintColor = symbol == "stop.circle.fill" ? .systemRed : nil
        item.button?.title = elapsed.isEmpty ? "" : " " + elapsed
        item.button?.toolTip = label
        item.button?.setAccessibilityLabel(label)
    }
    @objc private func clicked() {
        guard let button = item.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            let menu = NSMenu()
            let settings = NSMenuItem(title: "Settings…", action: #selector(settingsClicked), keyEquivalent: "")
            settings.target = self; settings.isEnabled = session == nil
            menu.autoenablesItems = false
            menu.addItem(settings)
            let reveal = NSMenuItem(title: "Show Last GIF in Finder", action: #selector(revealClicked), keyEquivalent: "")
            reveal.target = self; reveal.isEnabled = lastSaved != nil
            menu.addItem(reveal)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "Quit Rekordit", action: #selector(quitClicked), keyEquivalent: "")
            quit.target = self; quit.isEnabled = session == nil
            menu.addItem(quit)
            menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.minY), in: button)
        } else if let session { session.menuClicked() }
        else { action(0) }
    }
    @objc private func settingsClicked() { action(1) }
    @objc private func revealClicked() { if let lastSaved { NSWorkspace.shared.activateFileViewerSelecting([lastSaved]) } }
    @objc private func quitClicked() { NSApp.terminate(nil) }
}

@_cdecl("rekordit_begin")
public func rekorditBegin(_ fps: Int32, _ cursor: Int32, _ dark: Int32, _ quick: Int32,
                         _ completed: @escaping @convention(c) (UnsafePointer<CChar>?) -> Void) {
    DispatchQueue.main.async {
        guard session == nil else { completed(nil); return }
        session = CaptureSession(fps: Int(fps), cursor: cursor != 0, dark: dark != 0, quick: quick != 0, completed: completed)
        session?.selectArea()
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var selection = CGRect.zero { didSet { needsDisplay = true } }
    var changed: ((CGRect) -> Void)?
    var cancelled: (() -> Void)?
    var released: (() -> Void)?
    private var start = CGPoint.zero
    private var original = CGRect.zero
    private var handle = -2 // -2 draws, -1 moves, 0...7 resizes.

    private var handles: [CGPoint] {
        let r = selection
        return [CGPoint(x:r.minX,y:r.minY), CGPoint(x:r.midX,y:r.minY), CGPoint(x:r.maxX,y:r.minY),
                CGPoint(x:r.maxX,y:r.midY), CGPoint(x:r.maxX,y:r.maxY), CGPoint(x:r.midX,y:r.maxY),
                CGPoint(x:r.minX,y:r.maxY), CGPoint(x:r.minX,y:r.midY)]
    }

    override func draw(_ dirtyRect: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        if !selection.isEmpty { shade.appendRect(selection) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.32).setFill()
        shade.fill()
        if selection.isEmpty {
            let text = "Drag to select an area · Escape to cancel" as NSString
            text.draw(at: CGPoint(x: 28, y: 28), withAttributes: [.foregroundColor: NSColor.white,
                      .font: NSFont.systemFont(ofSize: 18, weight: .medium)])
            return
        }
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: selection)
        outline.lineWidth = 2
        outline.stroke()
        NSColor.white.setFill()
        for point in handles { NSBezierPath(roundedRect: CGRect(x:point.x-4,y:point.y-4,width:8,height:8), xRadius:2,yRadius:2).fill() }
        let text = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
        text.draw(at: CGPoint(x: selection.minX + 8, y: max(8, selection.minY - 25)),
                  withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.monospacedDigitSystemFont(ofSize:14,weight:.medium)])
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil)
        original = selection
        handle = selection.isEmpty ? -2 : handles.firstIndex(where: { abs($0.x-start.x)<10 && abs($0.y-start.y)<10 }) ?? (selection.contains(start) ? -1 : -2)
        if handle == -2 { selection = .zero; changed?(selection) }
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if handle == -2 { selection = draggedRect(from: start, to: point, within: bounds) }
        else if handle == -1 { selection = movedRect(original, dx:point.x-start.x,dy:point.y-start.y,within:bounds) }
        else { selection = resizedRect(original,handle:handle,to:point,within:bounds) }
        changed?(selection)
    }
    override func mouseUp(with event: NSEvent) { mouseDragged(with: event); released?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelled?() } else { super.keyDown(with: event) }
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        if !selection.isEmpty { addCursorRect(selection, cursor: .openHand) }
        for (i, p) in handles.enumerated() where !selection.isEmpty {
            addCursorRect(CGRect(x:p.x-8,y:p.y-8,width:16,height:16), cursor: i == 1 || i == 5 ? .resizeUpDown : .resizeLeftRight)
        }
    }
}

// ponytail: PNGs spool to disk, not RAM. Use AVAssetWriter if long recordings make the spool too large.
// Mutable frame state is confined to queue.
private final class FrameSpool: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.rekordit.frames", qos: .userInitiated)
    let directory: URL
    let started = ProcessInfo.processInfo.systemUptime
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var frames: [Frame] = []
    private var failed = false
    var onError: ((Error) -> Void)?

    init(directory: URL) { self.directory = directory }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !failed, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        autoreleasepool {
            let image = CIImage(cvPixelBuffer: buffer)
            guard let cg = context.createCGImage(image, from: image.extent) else { fail("The captured frame could not be decoded."); return }
            let url = directory.appendingPathComponent("frame-\(frames.count).png")
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fail("Could not create a temporary frame. Check available disk space."); return }
            CGImageDestinationAddImage(destination, cg, nil)
            guard CGImageDestinationFinalize(destination) else { fail("Could not write a captured frame. Check available disk space."); return }
            frames.append(Frame(url: url, time: ProcessInfo.processInfo.systemUptime - started))
        }
    }
    private func fail(_ message: String) {
        failed = true
        onError?(NSError(domain:"Rekordit",code:1,userInfo:[NSLocalizedDescriptionKey:message]))
    }

    func encode(duration: Double) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let url = try encodeGIF(frames:self.frames,directory:self.directory,duration:duration)
                    for frame in self.frames { try? FileManager.default.removeItem(at: frame.url) }
                    continuation.resume(returning: url)
                } catch { continuation.resume(throwing:error) }
            }
        }
    }
}

@MainActor private final class CaptureSession: NSObject, SCStreamDelegate, NSWindowDelegate {
    private enum State { case selecting, starting, recording, encoding, preview, finished }
    private var state = State.selecting
    private var errorMessage: String?
    private let fps: Int
    private let cursor: Bool
    private let dark: Bool
    private let quick: Bool
    private let completed: @convention(c) (UnsafePointer<CChar>?) -> Void
    private var overlays: [(NSPanel, SelectionView, NSScreen)] = []
    private var activeScreen: NSScreen?
    private var selected = CGRect.zero
    private var toolbar: NSPanel?
    private var statusLabel: NSTextField?
    private var recordButton: NSButton?
    private var timer: Timer?
    private var stream: SCStream?
    private var spool: FrameSpool?
    private var directory: URL?
    private var preview: NSWindow?
    private var gif: URL?
    private var terminationObserver: NSObjectProtocol?
    private var escapeMonitor: Any?

    init(fps: Int, cursor: Bool, dark: Bool, quick: Bool, completed: @escaping @convention(c) (UnsafePointer<CChar>?) -> Void) {
        self.fps = fps; self.cursor = cursor; self.dark = dark; self.quick = quick; self.completed = completed
        super.init()
        terminationObserver = NotificationCenter.default.addObserver(forName:NSApplication.willTerminateNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.cleanFiles() } }
    }

    func selectArea() {
        state = .selecting
        menuBar?.update("viewfinder", label: "Rekordit — Drag an area; Escape to cancel")
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            if event.keyCode == 53, self?.state == .selecting { self?.finish(); return nil }
            return event
        }
        for screen in NSScreen.screens {
            let panel = OverlayPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.title = "Select Area"
            panel.level = quick ? .floating : .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
            let view = SelectionView(frame:CGRect(origin:.zero,size:screen.frame.size))
            view.changed = { [weak self, weak view] rect in
                guard let self, self.state == .selecting else { return }
                self.activeScreen = screen; self.selected = rect
                for (_, other, _) in self.overlays where other !== view { other.selection = .zero }
                if let view { view.window?.invalidateCursorRects(for:view) }
                if !self.quick { self.showToolbar() }
            }
            view.released = { [weak self] in
                guard let self, self.quick, self.selected.width >= 24, self.selected.height >= 24 else { return }
                self.record()
            }
            view.cancelled = { [weak self] in if self?.state == .selecting { self?.finish() } }
            panel.contentView = view
            panel.makeFirstResponder(view)
            overlays.append((panel,view,screen))
            panel.orderFrontRegardless()
        }
        overlays.first?.0.makeKey()
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title:title,target:self,action:action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize:15,weight:.medium)
        return button
    }

    private func showToolbar() {
        guard let screen = activeScreen, selected.width >= 24, selected.height >= 24 else { toolbar?.orderOut(nil); return }
        if toolbar == nil {
            let panel = NSPanel(contentRect:CGRect(x:0,y:0,width:290,height:54),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.level = NSWindow.Level(rawValue:NSWindow.Level.screenSaver.rawValue+1)
            panel.title = "Capture Controls"
            panel.isFloatingPanel = true
            panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
            panel.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
            panel.backgroundColor = dark ? NSColor(calibratedRed:0.125,green:0.145,blue:0.188,alpha:1) : .windowBackgroundColor
            panel.hasShadow = true
            let label = NSTextField(labelWithString:"Ready")
            label.font = .monospacedDigitSystemFont(ofSize:14,weight:.medium)
            let record = button("Record", action:#selector(record))
            record.bezelColor = .systemBlue
            let cancel = button("Cancel",action:#selector(cancel))
            let stack = NSStackView(views:[label,record,cancel])
            stack.orientation = .horizontal; stack.spacing = 12; stack.alignment = .centerY
            stack.frame = CGRect(x:12,y:8,width:266,height:38)
            stack.autoresizingMask = [.width,.height]
            panel.contentView?.addSubview(stack)
            toolbar = panel; statusLabel = label; recordButton = record
        }
        let x = min(max(screen.frame.minX + selected.midX - 145, screen.frame.minX+8), screen.frame.maxX-298)
        var y = screen.frame.maxY - selected.maxY - 66
        if y < screen.frame.minY+8 { y = min(screen.frame.maxY-62, screen.frame.maxY-selected.minY+12) }
        toolbar?.setFrameOrigin(CGPoint(x:x,y:y))
        toolbar?.orderFrontRegardless()
    }

    @objc private func cancel() { if state == .selecting { finish() } }
    @objc private func record() {
        guard state == .selecting, let screen = activeScreen else { return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            alert("Screen Recording permission is needed", "Allow Rekordit in System Settings → Privacy & Security → Screen Recording, then reopen the app.")
            finish(); return
        }
        state = .starting
        menuBar?.update("hourglass", label: "Rekordit — Starting recording")
        recordButton?.isEnabled = false
        statusLabel?.stringValue = "Starting…"
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly:true)
                guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                      let display = content.displays.first(where:{$0.displayID == id}) else { throw NSError(domain:"Rekordit",code:3,userInfo:[NSLocalizedDescriptionKey:"The selected display is no longer connected."]) }
                let excluded = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                guard !excluded.isEmpty else { throw NSError(domain:"Rekordit",code:4,userInfo:[NSLocalizedDescriptionKey:"Cannot exclude the recording controls from capture. Please reopen the app."]) }
                let filter = SCContentFilter(display:display,excludingApplications:excluded,exceptingWindows:[])
                let config = SCStreamConfiguration()
                config.sourceRect = selected.integral
                let scale = CGFloat(CGDisplayPixelsWide(id)) / display.frame.width
                config.width = Int(config.sourceRect.width * scale)
                config.height = Int(config.sourceRect.height * scale)
                config.minimumFrameInterval = CMTime(value:1,timescale:Int32(fps))
                config.showsCursor = cursor
                config.queueDepth = 3
                config.pixelFormat = kCVPixelFormatType_32BGRA
                if #available(macOS 13.0, *) { config.capturesAudio = false }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Rekordit-\(UUID().uuidString)",isDirectory:true)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                directory = folder
                let writer = FrameSpool(directory:folder)
                writer.onError = { [weak self] error in DispatchQueue.main.async { self?.stop(error:error) } }
                spool = writer
                let capture = SCStream(filter:filter,configuration:config,delegate:self)
                try capture.addStreamOutput(writer,type:.screen,sampleHandlerQueue:writer.queue)
                stream = capture
                try await capture.startCapture()
                state = .recording
                for (panel, _, _) in overlays { panel.orderOut(nil) }
                recordButton?.title = "Stop"; recordButton?.action = #selector(stopClicked); recordButton?.isEnabled = true
                if let stack = toolbar?.contentView?.subviews.first as? NSStackView, let cancel = stack.views.last as? NSButton { cancel.isHidden = true }
                updateElapsed()
                timer = Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { [weak self] _ in Task { @MainActor in self?.updateElapsed() } }
            } catch {
                if let stream { try? await stream.stopCapture() }
                alert("Could not record this area",error.localizedDescription)
                finish()
            }
        }
    }

    private func updateElapsed() {
        let seconds = Int(ProcessInfo.processInfo.systemUptime - (spool?.started ?? ProcessInfo.processInfo.systemUptime))
        let elapsed = String(format:"%02d:%02d",seconds/60,seconds%60)
        statusLabel?.stringValue = elapsed
        menuBar?.update("stop.circle.fill", label: quick ? "Rekordit — Stop recording and save GIF" : "Rekordit — Stop recording and preview", elapsed: elapsed)
    }
    func menuClicked() {
        if state == .selecting { finish() }
        else if state == .recording { stop(error:nil) }
    }
    @objc private func stopClicked() { stop(error:nil) }
    private func stop(error: Error?) {
        guard state == .recording else { return }
        state = .encoding
        menuBar?.update("hourglass", label: "Rekordit — Saving GIF")
        timer?.invalidate(); timer = nil
        recordButton?.isEnabled = false
        statusLabel?.stringValue = "Preparing…"
        let duration = ProcessInfo.processInfo.systemUptime - (spool?.started ?? ProcessInfo.processInfo.systemUptime)
        Task {
            do {
                var stopError = error
                do { try await stream?.stopCapture() } catch { stopError = stopError ?? error }
                guard let spool else { throw CocoaError(.fileReadUnknown) }
                gif = try await spool.encode(duration:duration)
                closeOverlays()
                if quick, let gif {
                    do {
                        let desktop = try FileManager.default.url(for:.desktopDirectory,in:.userDomainMask,appropriateFor:nil,create:false)
                        let destination = try saveRecording(gif, in: desktop)
                        menuBar?.lastSaved = destination
                        if let stopError { errorMessage = "GIF saved, but recording stopped: " + stopError.localizedDescription }
                        finish()
                        return
                    } catch {
                        showPreview()
                        alert("Could not save to Desktop", "Your recording is kept here. Choose Save GIF to save it elsewhere. " + error.localizedDescription)
                        return
                    }
                }
                showPreview()
                if let stopError { alert("Recording stopped",stopError.localizedDescription) }
            } catch {
                alert("Could not prepare the recording",error.localizedDescription)
                finish()
            }
        }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.stop(error:error) }
    }

    private func showPreview() {
        guard let gif, let image = NSImage(contentsOf:gif) else { alert("Preview unavailable","The recorded GIF could not be read."); finish(); return }
        state = .preview
        menuBar?.update("viewfinder", label: "Rekordit — Recording preview open")
        let window = NSWindow(contentRect:CGRect(x:0,y:0,width:640,height:460),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        window.title = "Recording preview"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
        window.minSize = NSSize(width:420,height:300)
        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.setAccessibilityLabel("Preview of the recorded area")
        let save = button("Save GIF…",action:#selector(saveGif)); save.bezelColor = .systemBlue
        let again = button("Record Again",action:#selector(recordAgain))
        let privacy = NSTextField(labelWithString:"Files stay on your Mac.")
        privacy.textColor = .secondaryLabelColor
        let actions = NSStackView(views:[privacy,again,save]); actions.orientation = .horizontal; actions.spacing = 16
        let stack = NSStackView(views:[imageView,actions]); stack.orientation = .vertical; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-20),stack.topAnchor.constraint(equalTo:content.topAnchor,constant:20),stack.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-20),imageView.widthAnchor.constraint(equalTo:stack.widthAnchor),actions.heightAnchor.constraint(equalToConstant:40)])
        }
        window.center(); window.makeKeyAndOrderFront(nil)
        preview = window
    }

    @objc private func saveGif() {
        guard state == .preview, let gif, let preview else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "Recording.gif"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for:preview) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".rekordit-\(UUID().uuidString).gif")
            do {
                try FileManager.default.copyItem(at:gif,to:temporary)
                if FileManager.default.fileExists(atPath:url.path) { _ = try FileManager.default.replaceItemAt(url,withItemAt:temporary) }
                else { try FileManager.default.moveItem(at:temporary,to:url) }
                preview.title = "Saved — \(url.lastPathComponent)"
            } catch {
                try? FileManager.default.removeItem(at:temporary)
                self.alert("Could not save the GIF",error.localizedDescription)
            }
        }
    }
    @objc private func recordAgain() {
        preview?.delegate = nil; preview?.close(); preview = nil
        cleanFiles(); gif = nil; spool = nil; stream = nil
        selectArea()
    }
    func windowWillClose(_ notification: Notification) { if state == .preview { finish() } }
    private func closeOverlays() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        timer?.invalidate(); timer = nil
        for (panel,_,_) in overlays { panel.close() }
        overlays.removeAll(); toolbar?.close(); toolbar = nil; recordButton = nil; statusLabel = nil
    }
    private func cleanFiles() { if let directory { try? FileManager.default.removeItem(at:directory) }; directory = nil }
    private func finish() {
        guard state != .finished else { return }
        state = .finished
        menuBar?.update("viewfinder", label: menuBar?.lastSaved == nil ? "Rekordit — Select Area" : "Rekordit — GIF saved to Desktop; click to record again")
        closeOverlays()
        preview?.delegate = nil; preview?.close(); preview = nil
        cleanFiles()
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        if let errorMessage { errorMessage.withCString { completed($0) } } else { completed(nil) }
        session = nil
    }
    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle:"OK")
        if let preview { alert.beginSheetModal(for:preview) }
        else { errorMessage = title + ": " + message }
    }
}
