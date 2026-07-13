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
    /// The `IO<Sockets.Capabilities>` strategies exercised by the
    /// parameterized integration tests.
    ///
    /// - `.blocking` — the shipped blocking factory (`IO.blocking()` +
    ///   `.blocking` listener factory): fds stay in kernel blocking mode
    ///   and `ready` is a no-op.
    /// - `.reactive` — the test-support reactive factory (`makeReactiveIO()`
    ///   + `.reactive` listener factory): fds are `O_NONBLOCK` and `ready`
    ///   is a blocking `poll(2)`. This cell exists only to exercise the
    ///   reactive code paths (accept loop, connect sequence, EAGAIN-retry
    ///   read/write); the real reactor / proactor factories are swift-io's
    ///   territory (Phase 2B / 2C).
    ///
    /// Fresh strategy resources are created per test invocation to
    /// isolate state between cells.
    enum Strategy: Sendable, CaseIterable {
        case blocking
        case reactive
    }
}

extension Sockets.TCP.Listener.Tests.Strategy {
    /// Construct an `IO<Sockets.Capabilities>` for the strategy.
    ///
    /// Used for both the server-side listener pairing (``makeServer(_:)``)
    /// and the client-side ``Sockets/TCP/Connection/connect(to:io:)`` path.
    func makeIO() -> IO<Sockets.Capabilities> {
        switch self {
        case .blocking: return .blocking()
        case .reactive: return makeReactiveIO()
        }
    }

    /// Construct a server `IO` + `Listener` pair for the strategy,
    /// bound to IPv4 loopback on a kernel-assigned ephemeral port. Each
    /// cell pairs the strategy-appropriate listener factory (`.blocking`
    /// for the blocking strategy, `.reactive` for the reactive one).
    static func makeServer(_ strategy: Self) async throws -> (IO<Sockets.Capabilities>, Sockets.TCP.Listener) {
        let io = strategy.makeIO()
        let listener: Sockets.TCP.Listener
        switch strategy {
        case .blocking:
            listener = try Sockets.TCP.Listener.blocking(
                address: Kernel.Socket.Address.IPv4.loopback(port: 0),
                io: io
            )
        case .reactive:
            listener = try Sockets.TCP.Listener.reactive(
                address: Kernel.Socket.Address.IPv4.loopback(port: 0),
                io: io
            )
        }
        return (io, listener)
    }
}
