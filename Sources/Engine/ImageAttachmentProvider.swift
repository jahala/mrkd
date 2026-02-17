import AppKit

/// Manages async image loading for markdown images
final class ImageAttachmentProvider {

    private let fileBaseURL: URL
    private let imageCache = NSCache<NSString, NSImage>()
    private let downloadQueue = DispatchQueue(label: "com.mrkd.images", qos: .utility, attributes: .concurrent)
    private var pressureObserver: NSObjectProtocol?
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    init(fileBaseURL: URL) {
        self.fileBaseURL = fileBaseURL
        imageCache.totalCostLimit = 200 * 1024 * 1024 // 200MB budget

        // Listen for memory pressure notifications and flush cache
        pressureObserver = NotificationCenter.default.addObserver(
            forName: MemoryMonitor.memoryPressureNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.imageCache.removeAllObjects()
        }
    }

    deinit {
        if let observer = pressureObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Load image from URL string (can be relative path, absolute path, or HTTP URL)
    func loadImage(from urlString: String, completion: @escaping (NSImage?) -> Void) {
        // Check cache first
        if let cached = imageCache.object(forKey: urlString as NSString) {
            completion(cached)
            return
        }

        downloadQueue.async { [weak self] in
            guard let self = self else { return }
            let image: NSImage?

            if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
                image = self.loadRemoteImage(urlString)
            } else if urlString.hasPrefix("data:") {
                image = self.loadBase64Image(urlString)
            } else {
                image = self.loadLocalImage(urlString)
            }

            // Downscale if too large
            let processed = image.flatMap { self.downscaleIfNeeded($0) }

            if let processed = processed {
                self.imageCache.setObject(processed, forKey: urlString as NSString,
                                          cost: Int(processed.size.width * processed.size.height * 4))
            }

            DispatchQueue.main.async {
                completion(processed)
            }
        }
    }

    private func loadLocalImage(_ path: String) -> NSImage? {
        let resolvedURL: URL
        if path.hasPrefix("/") {
            resolvedURL = URL(fileURLWithPath: path)
        } else {
            resolvedURL = fileBaseURL.deletingLastPathComponent().appendingPathComponent(path)
        }
        return NSImage(contentsOf: resolvedURL)
    }

    private func loadRemoteImage(_ urlString: String) -> NSImage? {
        guard let url = URL(string: urlString) else { return nil }
        var resultImage: NSImage?
        let semaphore = DispatchSemaphore(value: 0)

        let task = urlSession.dataTask(with: url) { data, response, error in
            defer { semaphore.signal() }
            guard let data = data, error == nil else { return }
            resultImage = NSImage(data: data)
        }
        task.resume()
        semaphore.wait()

        return resultImage
    }

    private func loadBase64Image(_ dataURI: String) -> NSImage? {
        // Format: data:image/png;base64,iVBOR...
        guard let commaIndex = dataURI.firstIndex(of: ",") else { return nil }
        let base64String = String(dataURI[dataURI.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64String) else { return nil }
        return NSImage(data: data)
    }

    private func downscaleIfNeeded(_ image: NSImage) -> NSImage {
        let maxDimension: CGFloat = 2048
        let size = image.size

        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }

        let scale = maxDimension / max(size.width, size.height)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        return NSImage(size: newSize, flipped: false) { rect in
            image.draw(in: rect, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
            return true
        }
    }
}
