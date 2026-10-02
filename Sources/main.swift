import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - Local file scheme

/// Serves the markdown file's own directory (images, and anything else it links
/// to) over `mdfile://`.
///
/// `loadFileURL(_, allowingReadAccessTo:)` cannot grant the webview access
/// across a mount point: the app lives on the system volume and documents
/// usually do not, so relative images never loaded no matter how wide the
/// grant. Reading the bytes here sidesteps the file-URL sandbox entirely.
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdfile"

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let fileURL = url.convertedToScheme("file"),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)"])!
        // Served synchronously: the task cannot be stopped mid-flight, which is
        // what would otherwise make the didReceive calls throw.
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// MARK: - Document window

final class DocumentWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    let fileURL: URL
    private var webView: WKWebView!
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var lastModified: Date?
    private var pageReady = false
    var onClose: (() -> Void)?

    init(fileURL: URL) {
        self.fileURL = fileURL
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 940),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = fileURL.lastPathComponent
        window.tabbingMode = .disallowed
        window.center()
        window.setFrameAutosaveName("MDViewerWindow")
        super.init(window: window)
        window.delegate = self

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(LocalFileSchemeHandler(),
                                          forURLScheme: LocalFileSchemeHandler.scheme)
        webView = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        window.contentView!.addSubview(webView)

        let resources = Bundle.main.resourceURL!
        let viewerPage = resources.appendingPathComponent("viewer.html")
        // Only our own assets load as file URLs; the document's own directory is
        // served over mdfile:// instead. The grant must be an ancestor of the
        // page or WebKit refuses the load outright.
        webView.loadFileURL(viewerPage, allowingReadAccessTo: resources)
        startMonitoring()
        startPolling()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Rendering

    func render() {
        guard pageReady else { return }
        let text = (try? String(contentsOf: fileURL, encoding: .utf8))
            ?? (try? String(contentsOf: fileURL, encoding: .isoLatin1))
            ?? "*Unable to read \(fileURL.path)*"
        guard let baseURL = fileURL.deletingLastPathComponent()
            .convertedToScheme(LocalFileSchemeHandler.scheme) else { return }
        let baseHref = baseURL.absoluteString
        guard let textJSON = jsonString(text), let baseJSON = jsonString(baseHref) else { return }
        lastModified = modificationDate()
        webView.evaluateJavaScript("renderMarkdown(\(textJSON), \(baseJSON));", completionHandler: nil)
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    private func jsonString(_ s: String) -> String? {
        guard let data = try? JSONEncoder().encode(s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: File watching (handles Vim-style save-via-rename)

    private func startMonitoring() {
        fileMonitor?.cancel()
        fileMonitor = nil
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.fileMonitor?.data ?? []
            if flags.contains(.delete) || flags.contains(.rename) {
                // Editors that write a new file and swap it in: re-attach to the new inode.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.startMonitoring()
                    self.render()
                }
            } else {
                self.render()
            }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        fileMonitor = source
    }

    // MARK: Modification-date polling (SMB/iCloud/Dropbox deliver no vnode events)

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.pageReady else { return }
            let current = self.modificationDate()
            if current != self.lastModified { self.render() }
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        render()
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
        // The viewer page itself (including #anchor navigation within it).
        if url.isFileURL, url.deletingFragment().lastPathComponent == "viewer.html" {
            return decisionHandler(.allow)
        }
        decisionHandler(.cancel)
        // Links in the document resolve against the mdfile:// base href.
        let target = url.scheme == LocalFileSchemeHandler.scheme
            ? (url.convertedToScheme("file") ?? url)
            : url
        if target.isFileURL, ["md", "markdown", "mdown", "mkd"].contains(target.pathExtension.lowercased()) {
            (NSApp.delegate as? AppDelegate)?.openDocument(target)
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    // MARK: Menu actions (reached via the responder chain)

    @objc func reloadDocument(_ sender: Any?) { render() }
    @objc func zoomIn(_ sender: Any?) { webView.pageZoom = min(webView.pageZoom + 0.1, 3.0) }
    @objc func zoomOut(_ sender: Any?) { webView.pageZoom = max(webView.pageZoom - 0.1, 0.5) }
    @objc func actualSize(_ sender: Any?) { webView.pageZoom = 1.0 }
    @objc func revealInFinder(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func windowWillClose(_ notification: Notification) {
        fileMonitor?.cancel()
        fileMonitor = nil
        pollTimer?.invalidate()
        pollTimer = nil
        onClose?()
    }
}

private extension URL {
    /// Same path, different scheme, fragment dropped — a fragment would defeat
    /// both `Data(contentsOf:)` and the path extension checks.
    func convertedToScheme(_ scheme: String) -> URL? {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.scheme = scheme
        components?.fragment = nil
        return components?.url
    }

    func deletingFragment() -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url ?? self
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [DocumentWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { openDocument(url) }
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        showOpenPanel()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func openDocument(_ url: URL) {
        let url = url.standardizedFileURL
        if let existing = controllers.first(where: { $0.fileURL.standardizedFileURL == url }) {
            existing.render()  // the watcher may have missed changes (e.g. on SMB shares)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = DocumentWindowController(fileURL: url)
        controller.onClose = { [weak self, weak controller] in
            self?.controllers.removeAll { $0 === controller }
        }
        controllers.append(controller)
        controller.showWindow(nil)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    @objc func openDocumentAction(_ sender: Any?) { showOpenPanel() }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText]
        for ext in ["md", "markdown", "mdown", "mkd"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls { openDocument(url) }
        } else if NSApp.windows.allSatisfy({ !$0.isVisible }) {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Menu

func buildMainMenu() -> NSMenu {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenuItem.submenu = appMenu
    appMenu.addItem(withTitle: "About MDViewer",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide MDViewer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit MDViewer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    let fileMenuItem = NSMenuItem()
    mainMenu.addItem(fileMenuItem)
    let fileMenu = NSMenu(title: "File")
    fileMenuItem.submenu = fileMenu
    fileMenu.addItem(withTitle: "Open…", action: #selector(AppDelegate.openDocumentAction(_:)), keyEquivalent: "o")
    fileMenu.addItem(withTitle: "Reveal in Finder",
                     action: #selector(DocumentWindowController.revealInFinder(_:)), keyEquivalent: "")
    fileMenu.addItem(.separator())
    fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    let editMenu = NSMenu(title: "Edit")
    editMenuItem.submenu = editMenu
    editMenu.addItem(withTitle: "Copy", action: NSSelectorFromString("copy:"), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Select All", action: NSSelectorFromString("selectAll:"), keyEquivalent: "a")
    editMenu.addItem(.separator())
    let findItem = NSMenuItem(title: "Find…", action: NSSelectorFromString("performTextFinderAction:"), keyEquivalent: "f")
    findItem.tag = NSTextFinder.Action.showFindInterface.rawValue
    editMenu.addItem(findItem)

    let viewMenuItem = NSMenuItem()
    mainMenu.addItem(viewMenuItem)
    let viewMenu = NSMenu(title: "View")
    viewMenuItem.submenu = viewMenu
    viewMenu.addItem(withTitle: "Reload", action: #selector(DocumentWindowController.reloadDocument(_:)), keyEquivalent: "r")
    viewMenu.addItem(.separator())
    viewMenu.addItem(withTitle: "Actual Size", action: #selector(DocumentWindowController.actualSize(_:)), keyEquivalent: "0")
    viewMenu.addItem(withTitle: "Zoom In", action: #selector(DocumentWindowController.zoomIn(_:)), keyEquivalent: "+")
    viewMenu.addItem(withTitle: "Zoom Out", action: #selector(DocumentWindowController.zoomOut(_:)), keyEquivalent: "-")

    let windowMenuItem = NSMenuItem()
    mainMenu.addItem(windowMenuItem)
    let windowMenu = NSMenu(title: "Window")
    windowMenuItem.submenu = windowMenu
    windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    NSApp.windowsMenu = windowMenu

    return mainMenu
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.mainMenu = buildMainMenu()
app.run()
