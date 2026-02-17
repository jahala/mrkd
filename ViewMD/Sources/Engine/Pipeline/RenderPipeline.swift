import AppKit
import cmark_gfm
import cmark_gfm_extensions

// The pipeline result delivered to the main thread
struct RenderResult {
    let attributedString: NSAttributedString
    let theme: Theme
}

// Pipeline that processes markdown -> attributed string on a background queue
final class RenderPipeline {

    private let workQueue = DispatchQueue(label: "com.mrkd.render", qos: .userInitiated)
    private var currentTask: DispatchWorkItem?

    // Cancel any in-flight render
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // Render markdown asynchronously, delivering result on main thread
    func render(markdown: String, theme: Theme, completion: @escaping (RenderResult) -> Void) {
        cancel()

        let task = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            let attributed = MarkdownRenderer.render(markdown, theme: theme)

            // Capture task reference to check inside main queue block
            let workItem = self.currentTask
            DispatchQueue.main.async {
                guard workItem?.isCancelled == false else { return }
                completion(RenderResult(attributedString: attributed, theme: theme))
            }
        }

        currentTask = task
        workQueue.async(execute: task)
    }

    /// Progressive render for larger files: delivers a first-screen snapshot
    /// as soon as the first ~30 top-level blocks are rendered, then delivers
    /// the complete result once the full document is done.
    func renderProgressive(
        markdown: String,
        theme: Theme,
        onFirstScreen: @escaping (RenderResult) -> Void,
        onComplete: @escaping (RenderResult) -> Void
    ) {
        cancel()

        let task = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Capture task reference to check inside main queue blocks
            let workItem = self.currentTask

            let full = MarkdownRenderer.renderProgressive(
                markdown,
                theme: theme,
                firstScreenBlocks: 30
            ) { firstScreen in
                // Deliver first-screen snapshot immediately
                DispatchQueue.main.async {
                    guard workItem?.isCancelled == false else { return }
                    onFirstScreen(RenderResult(attributedString: firstScreen, theme: theme))
                }
            }

            DispatchQueue.main.async {
                guard workItem?.isCancelled == false else { return }
                onComplete(RenderResult(attributedString: full, theme: theme))
            }
        }

        currentTask = task
        workQueue.async(execute: task)
    }
}
