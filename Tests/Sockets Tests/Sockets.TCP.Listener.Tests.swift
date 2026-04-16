//
//  Sockets.TCP.Listener.Tests.swift
//  swift-sockets
//

import Testing
import Kernel
import Memory_Primitives
import IO
import Sockets

extension Sockets.TCP.Listener {
    /// Test-only namespace grouping integration tests for ``Sockets/TCP/Listener``.
    enum Tests {}
}

// MARK: - Strategy matrix for parameterized tests

extension Sockets.TCP.Listener.Tests {
    /// The `IO` strategies exercised by Phase 3A parameterized tests.
    ///
    /// Each case pairs a specific `IO` factory with the matching
    /// ``Sockets/TCP/Listener`` factory (`.blocking` for `IO.blocking()`;
    /// `.reactive` for reactor-backed strategies). The `completions` cell
    /// is Linux-only per swift-io constraint #3.
    ///
    /// Fresh reactor / proactor resources are created per test invocation
    /// to isolate state between cells.
    enum Strategy: Sendable, CaseIterable {
        case blocking
        case events
        #if os(Linux)
        case completions
        #endif
        case `default`

        /// Construct a server `IO` + `Listener` pair for the strategy,
        /// bound to IPv4 loopback on a kernel-assigned ephemeral port.
        static func makeServer(_ strategy: Strategy) async throws -> (IO, Sockets.TCP.Listener) {
            switch strategy {
            case .blocking:
                let io = IO.blocking()
                let listener = try Sockets.TCP.Listener.blocking(
                    address: .loopback(port: 0),
                    io: io
                )
                return (io, listener)
            case .events:
                let actor = try IO.Event.Actor()
                let io = IO.events(on: actor)
                let listener = try Sockets.TCP.Listener.reactive(
                    address: .loopback(port: 0),
                    io: io
                )
                return (io, listener)
            #if os(Linux)
            case .completions:
                let completions = try IO.Completions()
                let io = IO.completions(on: completions)
                let listener = try Sockets.TCP.Listener.reactive(
                    address: .loopback(port: 0),
                    io: io
                )
                return (io, listener)
            #endif
            case .default:
                // `IO.default()` returns a reactor-backed witness on both
                // Darwin (events) and Linux (completions) on the hosts
                // this gate runs on; the reactive listener factory is
                // the correct pairing.
                let io = IO.default()
                let listener = try Sockets.TCP.Listener.reactive(
                    address: .loopback(port: 0),
                    io: io
                )
                return (io, listener)
            }
        }
    }
}
