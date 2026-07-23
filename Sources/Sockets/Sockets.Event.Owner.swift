//
//  Sockets.Event.Owner.swift
//  swift-sockets
//

internal import IO
internal import Kernel
internal import Synchronization

extension Sockets.Event {
    /// Retains the owned events factory's actor and synchronizes lifecycle.
    ///
    /// The actor remains strongly retained for the full owner/IO lifetime so
    /// `IO.Runner.executor` always resolves against live backing storage. The
    /// mutex guards only the running/stopped transition; no borrow crosses
    /// suspension.
    internal final class Owner: Sendable {
        private let actor: Kernel.Event.Actor
        private let running: Mutex<Bool>

        internal init(_ actor: Kernel.Event.Actor) {
            self.actor = actor
            self.running = Mutex(true)
        }
    }
}

extension Sockets.Event.Owner {
    /// Resolves executor identity from the retained actor.
    internal var executor: UnownedSerialExecutor {
        unsafe actor.unownedExecutor
    }

    /// Takes a strong operation-local actor snapshot.
    internal func snapshot() throws(Sockets.Error) -> Kernel.Event.Actor {
        try running.withLock { running throws(Sockets.Error) in
            guard running else { throw .ioShutdown }
            return actor
        }
    }

    /// Takes a strong snapshot for the non-throwing close path.
    internal func optional() -> Kernel.Event.Actor? {
        running.withLock { $0 ? actor : nil }
    }

    /// Atomically marks the lifecycle stopped. Repeated calls are harmless.
    internal func stop() {
        running.withLock { running in
            running = false
        }
    }

    /// Rejects new work immediately, then joins the actor's idempotent
    /// shutdown on every call. Concurrent callers serialize through actor
    /// isolation and return only after their own shutdown hop completes.
    /// Actor, executor, and retained source storage remain alive until the
    /// owner/IO closure graph deinitializes.
    internal func shutdown() async {
        stop()
        await actor.shutdown()
    }
}
