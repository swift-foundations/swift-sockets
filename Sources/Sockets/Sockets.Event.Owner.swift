internal import IO
internal import Kernel
internal import Synchronization

extension Sockets.Event {

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

    internal var executor: UnownedSerialExecutor {
        unsafe actor.unownedExecutor
    }

    internal func snapshot() throws(Sockets.Error) -> Kernel.Event.Actor {
        try running.withLock { running throws(Sockets.Error) in
            guard running else { throw .ioShutdown }
            return actor
        }
    }

    internal func optional() -> Kernel.Event.Actor? {
        running.withLock { $0 ? actor : nil }
    }

    internal func stop() {
        running.withLock { running in
            running = false
        }
    }

    internal func shutdown() async {
        stop()
        await actor.shutdown()
    }
}
