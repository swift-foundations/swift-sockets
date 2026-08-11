//
//  IO+TCP.Listener.swift
//  swift-sockets
//

public import IO
internal import Kernel

extension IO where Capabilities == Sockets.TCP.Listener.Capabilities {
    /// The serial executor owned by this listener strategy.
    @inlinable
    public var unownedExecutor: UnownedSerialExecutor {
        unsafe runner.executor()
    }

    #if !os(Windows)
        /// Event-backed listener lifecycle using a caller-owned Event actor.
        public static func events(
            on actor: Kernel.Event.Actor
        ) -> IO<Sockets.TCP.Listener.Capabilities> {
            let strategy = Sockets.TCP.Listener.Events(actor: actor, owner: nil)
            let capabilities = Sockets.TCP.Listener.Capabilities(strategy: strategy)
            let runner = unsafe Self.Runner(
                executor: { unsafe strategy.executor },
                shutdown: {}
            )
            return IO(capabilities: capabilities, runner: runner)
        }

        /// Event-backed listener lifecycle owning a fresh Event actor.
        public static func events() throws(Kernel.Event.Failure) -> IO<Sockets.TCP.Listener.Capabilities> {
            let actor = try Kernel.Event.Actor()
            let owner = Sockets.Event.Owner(actor)
            let strategy = Sockets.TCP.Listener.Events(actor: actor, owner: owner)
            let capabilities = Sockets.TCP.Listener.Capabilities(strategy: strategy)
            let runner = unsafe Self.Runner(
                executor: { unsafe strategy.executor },
                shutdown: { await strategy.shutdown() }
            )
            return IO(capabilities: capabilities, runner: runner)
        }
    #endif

    internal func enlist(
        borrowing descriptor: borrowing Kernel.Descriptor
    ) throws(Sockets.Error) -> (
        operation: IO<Sockets.TCP.Listener.Capabilities>.Operation<
            Sockets.TCP.Accepted,
            Sockets.Error
        >,
        completion: IO<Sockets.TCP.Listener.Capabilities>.Completion
    ) {
        try capabilities.strategy.enlist(borrowing: descriptor)
    }

    internal func close(_ descriptor: consuming Kernel.Descriptor) async {
        await capabilities.strategy.close(consume descriptor)
    }
}
