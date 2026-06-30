import Foundation

/// Cross-process signals between Broadcast Upload Extension and main app (Darwin notify center).
enum BroadcastNotification {
    private static let started = "com.androidremote.broadcast.started" as CFString
    private static let finished = "com.androidremote.broadcast.finished" as CFString
    private static let failed = "com.androidremote.broadcast.failed" as CFString

    static func postStarted() {
        post(started)
    }

    static func postFinished() {
        post(finished)
    }

    static func postFailed() {
        post(failed)
    }

    static func observeStarted(_ handler: @escaping () -> Void) -> DarwinObserver {
        observe(started, handler: handler)
    }

    static func observeFinished(_ handler: @escaping () -> Void) -> DarwinObserver {
        observe(finished, handler: handler)
    }

    static func observeFailed(_ handler: @escaping () -> Void) -> DarwinObserver {
        observe(failed, handler: handler)
    }

    private static func post(_ name: CFString) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil,
            nil,
            true
        )
    }

    private static func observe(_ name: CFString, handler: @escaping () -> Void) -> DarwinObserver {
        let observer = DarwinObserver()
        observer.register(name: name, handler: handler)
        return observer
    }
}

final class DarwinObserver {
    private var token: UnsafeMutableRawPointer?

    func register(name: CFString, handler: @escaping () -> Void) {
        let box = Unmanaged.passRetained(HandlerBox(handler: handler))
        token = box.toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            token,
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<HandlerBox>.fromOpaque(observer).takeUnretainedValue().handler()
            },
            name,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        guard let token else { return }
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            token
        )
        Unmanaged<HandlerBox>.fromOpaque(token).release()
    }

    private final class HandlerBox {
        let handler: () -> Void
        init(handler: @escaping () -> Void) { self.handler = handler }
    }
}
