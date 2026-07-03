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
    /// ``BlockingIdleCPU`` process-CPU measurement free of sibling-test
    /// thread noise.
    @Suite(.serialized)
    enum Tests {}
}

// MARK: - Strategy matrix for parameterized tests

extension Sockets.TCP.Listener.Tests {
    /// The `IO<Sockets.Capabilities>` strategies exercised by the
    /// parameterized integration tests.
    ///
    /// Phase 2A ships the blocking strategy only, so the matrix holds a
    /// single cell. The events / completions cells (and the
    /// host-adaptive default) return in Phase 2B / 2C when swift-sockets
    /// wires its capability set to swift-io's reactor / proactor actors
    /// — re-add the cases here and `makeServer` picks up the pairing
    /// (`.blocking` listener factory for the blocking strategy;
    /// `.reactive` for reactor-backed strategies).
    ///
    /// Fresh strategy resources are created per test invocation to
    /// isolate state between cells.
    enum Strategy: Sendable, CaseIterable {
        case blocking

        /// Construct a server `IO` + `Listener` pair for the strategy,
        /// bound to IPv4 loopback on a kernel-assigned ephemeral port.
        static func makeServer(_ strategy: Self) async throws -> (IO<Sockets.Capabilities>, Sockets.TCP.Listener) {
            switch strategy {
            case .blocking:
                let io = IO<Sockets.Capabilities>.blocking()
                let listener = try Sockets.TCP.Listener.blocking(
                    address: .loopback(port: 0),
                    io: io
                )
                return (io, listener)
            }
        }
    }
}
