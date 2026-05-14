import AppKit
import Quartz

/// Quick Look preview shell. Hosts the same `MarkdownViewController` the
/// main app uses, so TOC sidebar, article-width cap, themed Open button,
/// fragment links, smart typography, and code-block rendering all match
/// the main app automatically. The only logic here is the QL contract
/// (`QLPreviewingController` protocol) and the file-size guard.
final class PreviewViewController: NSViewController, QLPreviewingController {

    private let maxFileSize = 10_000_000  // 10 MB

    private var markdownVC: MarkdownViewController?
    private var pendingHandler: ((Error?) -> Void)?
    private var renderObserver: NSObjectProtocol?

    override func loadView() {
        view = NSView()
        view.autoresizingMask = [.width, .height]
    }

    deinit {
        if let observer = renderObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? Int, size > maxFileSize {
                handler(makeError("File too large for preview"))
                return
            }

            FontRegistrar.registerBundledFonts()

            // Defer the completion until MVC posts its initial-render
            // notification. The QL host appears to snapshot or finalise
            // layout at `handler(nil)` time — calling it before the
            // async render completes leaves the TOC sidebar empty in
            // the displayed preview even though the body has rendered.
            pendingHandler = handler
            renderObserver = NotificationCenter.default.addObserver(
                forName: .markdownInitialRenderComplete,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                self.view.needsLayout = true
                self.view.layoutSubtreeIfNeeded()
                self.pendingHandler?(nil)
                self.pendingHandler = nil
                if let observer = self.renderObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.renderObserver = nil
                }
            }

            let vc = MarkdownViewController(fileURL: url)
            addChild(vc)
            vc.view.frame = view.bounds
            vc.view.autoresizingMask = [.width, .height]
            view.addSubview(vc.view)
            self.markdownVC = vc
        } catch {
            handler(error)
        }
    }

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "com.mrkd.qlplugin",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
