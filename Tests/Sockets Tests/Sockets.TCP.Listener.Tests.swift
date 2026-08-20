//
//  Sockets.TCP.Listener.Tests.swift
//  swift-sockets
//

import IO
import Kernel
import Sockets
import Testing

extension Sockets.TCP.Listener {
    /// Test-only namespace grouping integration tests for ``Sockets/TCP/Listener``.
    ///
    /// `.serialized` (inherited by every nested suite): these are
    /// real-network integration tests that each pin a server + client
    /// `IO<Sockets.Capabilities>` to shards of swift-io's process-scoped
    /// shared blocking-executor pool. Under swift-testing's default
    /// parallel execution, a server `accept(2)` blocking its shard while
    /// a sibling test needs that same shard deadlocks the finite pool.
    /// Serializing removes the cross-test shard contention, and keeps the
    /// `` `Blocking Idle CPU` `` process-CPU measurement free of sibling-test
    /// thread noise.
    @Suite(.serialized)
    enum Tests {}
}

// MARK: - Strategy matrix for parameterized tests

extension Sockets.TCP.Listener.Tests {
    /// The lawful listener strategy exercised by the integration tests.
    /// Blocking acceptance is intentionally absent because it cannot satisfy
    /// externally cancellable release and physical-join laws.
    enum Strategy: Sendable, CaseIterable {
        case events
    }
}

extension Sockets.TCP.Listener.Tests.Strategy {
    /// Constructs Event-backed connection IO for accepted and client sockets.
    func makeIO() throws(Kernel.Event.Failure) -> IO<Sockets.Capabilities> {
        try .events()
    }

    /// Constructs a server with a dedicated Event listener lifecycle.
    static func makeServer(
        _ strategy: Self
    ) async throws -> (IO<Sockets.Capabilities>, Sockets.TCP.Listener) {
        let io = try strategy.makeIO()
        let listenerIO: IO<Sockets.TCP.Listener.Capabilities> = try .events()
        let listener = try Sockets.TCP.Listener.open(
            address: Kernel.Socket.Address.IPv4.loopback(port: 0),
            listenerIO: listenerIO,
            connectionIO: io
        )
        return (io, listener)
    }
}
