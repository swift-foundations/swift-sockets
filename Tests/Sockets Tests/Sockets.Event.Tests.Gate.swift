//
//  Sockets.Event.Tests.Gate.swift
//  swift-sockets
//

/// One-shot test synchronization without blocking a reactor thread.
actor Gate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?
}

extension Gate {
    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        guard !opened else { return }
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
