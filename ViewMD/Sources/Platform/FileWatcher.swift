import Foundation

protocol FileWatcherDelegate: AnyObject {
    func fileWatcher(_ watcher: FileWatcher, didDetectChangeFor url: URL)
    func fileWatcher(_ watcher: FileWatcher, didDetectDeletionOf url: URL)
}

final class FileWatcher {
    weak var delegate: FileWatcherDelegate?
    private let url: URL
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.mrkd.filewatcher", qos: .utility)
    private var retryWorkItem: DispatchWorkItem?

    init(url: URL) {
        self.url = url
    }

    func start() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let flags = source.data

            if flags.contains(.delete) || flags.contains(.rename) {
                DispatchQueue.main.async {
                    self.delegate?.fileWatcher(self, didDetectDeletionOf: self.url)
                }
                self.restartAfterDeletion()
            } else if flags.contains(.write) {
                DispatchQueue.main.async {
                    self.delegate?.fileWatcher(self, didDetectChangeFor: self.url)
                }
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        self.source = source
        source.resume()
    }

    func stop() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        source?.cancel()
        source = nil
    }

    private func restartAfterDeletion() {
        source?.cancel()
        source = nil

        attemptRestart(retryCount: 0)
    }

    private func attemptRestart(retryCount: Int) {
        let maxRetries = 5
        guard retryCount < maxRetries else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            let fd = open(self.url.path, O_EVTONLY)
            if fd >= 0 {
                close(fd)
                self.start()
                DispatchQueue.main.async {
                    self.delegate?.fileWatcher(self, didDetectChangeFor: self.url)
                }
            } else {
                self.attemptRestart(retryCount: retryCount + 1)
            }
        }

        retryWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    deinit {
        stop()
    }
}
