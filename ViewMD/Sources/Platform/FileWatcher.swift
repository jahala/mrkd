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
        source?.cancel()
        source = nil
    }

    deinit {
        stop()
    }
}
