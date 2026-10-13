import Foundation

/// One owned transfer. Cancellation closes the connection, rather than merely hiding its UI.
final class UpdatePackageDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let configuration: URLSessionConfiguration
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var response: URLResponse?
    private var bytes = Data()
    private var cancelled = false
    private var progress: (@Sendable (Int64, Int64) -> Void)?

    init(configuration: URLSessionConfiguration = .default) { self.configuration = configuration }

    func download(_ url: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> (Data, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                self.progress = progress
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.dataTask(with: url)
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: { self.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        lock.lock(); self.response = response; lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        bytes.append(data)
        let received = Int64(bytes.count)
        let encoding = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Encoding")
        let total = (encoding == nil || encoding == "identity") ? (response?.expectedContentLength ?? -1) : -1
        let progress = progress
        lock.unlock()
        progress?(received, total)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        let response = response
        let data = bytes
        let cancelled = cancelled
        self.task = nil
        self.session = nil
        self.progress = nil
        lock.unlock()
        session.finishTasksAndInvalidate()
        if cancelled { continuation?.resume(throwing: CancellationError()) }
        else if let error { continuation?.resume(throwing: error) }
        else if let response { continuation?.resume(returning: (data, response)) }
        else { continuation?.resume(throwing: URLError(.badServerResponse)) }
    }
}
