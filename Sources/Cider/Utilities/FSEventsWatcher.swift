import Foundation
import CoreServices

/// Thin wrapper over the FSEvents C API for recursive directory watching.
/// Delivers changed paths on the main queue after a coalescing latency window.
final class FSEventsWatcher {
    typealias ChangeHandler = @Sendable ([String]) -> Void

    private let path: String
    private let latency: CFTimeInterval
    fileprivate let handler: ChangeHandler
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.cider.fsevents", qos: .utility)

    /// - Parameters:
    ///   - path: The directory to watch recursively.
    ///   - latency: Coalescing window in seconds (default 0.3s — balances responsiveness with burst handling).
    ///   - handler: Called on the main queue with an array of changed paths.
    init(path: String, latency: CFTimeInterval = 0.3, handler: @escaping ChangeHandler) {
        self.path = path
        self.latency = latency
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil else { return }

        let pathsToWatch = [path] as CFArray
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        var context = FSEventStreamContext(
            version: 0,
            info: selfPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fsEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, queue)
        FSEventStreamStart(newStream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

/// Free-function callback required by the FSEvents C API.
private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

    // eventPaths is a CFArray of CFString when kFSEventStreamCreateFlagUseCFTypes is set
    guard let cfPaths = unsafeBitCast(eventPaths, to: CFArray?.self) else { return }
    let count = CFArrayGetCount(cfPaths)
    var paths: [String] = []
    paths.reserveCapacity(count)

    for i in 0..<count {
        if let cfStr = unsafeBitCast(CFArrayGetValueAtIndex(cfPaths, i), to: CFString?.self) {
            paths.append(cfStr as String)
        }
    }

    guard !paths.isEmpty else { return }

    let handler = watcher.handler
    DispatchQueue.main.async {
        handler(paths)
    }
}
