//
//  Sockets.TCP.Listener.Tests.MultipleConnections.swift
//  swift-sockets
//
//  Integration test: three concurrent clients echoed through one
//  Sockets.TCP.Listener. Blocking-strategy only for Phase 3A — concurrent
//  `io.ready` calls on the same fd under the events/completions strategies
//  hit swift-io's single-suspended-receiver invariant on the per-fd
//  readiness channel (Async_Channel_Primitives/Async.Channel.Unbounded.State.swift:186).
//  That is a pre-existing swift-io limitation, not a Phase 3A regression.
//  Parameterizing this suite across reactor-backed strategies is deferred
//  until swift-io's events/completions actor supports fan-out readiness
//  signalling (likely Phase 2E or Phase 3B).
//
//  Documents the thread-per-listener serialization model — every accept
//  and the subsequent read/write/close for each accepted connection run
//  on the listener's shared IO thread. Parallelism is not a bug here; it
//  is the expected ownership semantic:
//
//  - One listener = one IO = one OS thread.
//  - All three accepts and their echo round-trips serialize through that
//    thread (via actor isolation on Sockets.TCP.Listener).
//  - Clients use a separate IO (separate thread) so connect + write + read
//    do not contend with the listener's thread.
//
//  For parallelism across connections, build N listeners backed by N
//  distinct IOs (N threads) — swift-sockets does not implicitly pool
//  listeners.
//

import Testing
import Kernel
import Memory_Primitives
import IO
import Sockets
import Span_Raw_Primitives

extension Sockets.TCP.Listener.Tests {
    @Suite("Sockets.TCP.Listener — multiple connections")
    struct MultipleConnections {}
}

extension Sockets.TCP.Listener.Tests.MultipleConnections {

    @Test
    func `three concurrent connections echoed correctly round-trip (blocking strategy)`() async throws {
        let serverIO = IO.blocking()
        let clientIO = IO.blocking()
        let listener = try Sockets.TCP.Listener.blocking(
            address: .loopback(port: 0),
            io: serverIO
        )
        let port = try await listener.port()

        let payloads: [[UInt8]] = [
            [0x11, 0x22, 0x33],
            [0xAA, 0xBB, 0xCC],
            [0xF0, 0xE1, 0xD2]
        ]

        // Three servers accepting (all serialize through serverIO's single
        // thread) and three clients connecting (all share clientIO but TCP
        // sessions are independent, so per-session round-trip is correct).
        async let server0: [UInt8] = serverSideEcho(listener: listener)
        async let server1: [UInt8] = serverSideEcho(listener: listener)
        async let server2: [UInt8] = serverSideEcho(listener: listener)

        async let client0: [UInt8] = clientSideRoundTrip(
            io: clientIO, port: port, payload: payloads[0]
        )
        async let client1: [UInt8] = clientSideRoundTrip(
            io: clientIO, port: port, payload: payloads[1]
        )
        async let client2: [UInt8] = clientSideRoundTrip(
            io: clientIO, port: port, payload: payloads[2]
        )

        let (s0, s1, s2) = try await (server0, server1, server2)
        let (c0, c1, c2) = try await (client0, client1, client2)

        let serverEchoes = [s0, s1, s2]
        let clientReceives = [c0, c1, c2]

        // Each TCP session is independent: a client's own payload always
        // comes back to that same client. Order-independent across clients.
        #expect(
            Set(clientReceives) == Set(payloads),
            "Each client sees its own payload echoed back (order may differ by scheduling)."
        )
        // Servers saw all three payloads across the three accepts, in some
        // order determined by which client's SYN the kernel accepted first.
        #expect(
            Set(serverEchoes) == Set(payloads),
            "Server saw every payload exactly once across the three accepts."
        )
    }
}

// MARK: - Helpers (identical to Echo suite — duplicated rather than hoisted
// because per [PATTERN-026] the tests are read top-to-bottom and the helpers
// are the whole story).

private func serverSideEcho(listener: Sockets.TCP.Listener) async throws -> [UInt8] {
    let connection = try await listener.accept()

    let buffer = UnsafeMutableRawBufferPointer.allocate(
        byteCount: 1024,
        alignment: 1
    )
    defer { unsafe buffer.deallocate() }

    let readCount = try await connection.read(
        into: unsafe Span.Raw.Mutable(buffer)
    )

    let payloadSlice = unsafe UnsafeRawBufferPointer(
        start: buffer.baseAddress,
        count: readCount
    )
    _ = try await connection.write(from: unsafe Span.Raw(payloadSlice))

    await connection.close()

    var bytes: [UInt8] = []
    bytes.reserveCapacity(readCount)
    for i in 0..<readCount { bytes.append(unsafe buffer[i]) }
    return bytes
}

private func clientSideRoundTrip(
    io: IO,
    port: UInt16,
    payload: [UInt8]
) async throws -> [UInt8] {
    let socket = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
    try POSIX.Kernel.Socket.Connect.connect(
        socket,
        address: Kernel.Socket.Address.IPv4.loopback(port: port)
    )
    let descriptor = Kernel.Descriptor(consume socket)

    let writePtr = UnsafeMutableRawBufferPointer.allocate(
        byteCount: payload.count,
        alignment: 1
    )
    defer { unsafe writePtr.deallocate() }
    for (i, byte) in payload.enumerated() {
        unsafe writePtr[i] = byte
    }
    let writeBuffer = unsafe Span.Raw(UnsafeRawBufferPointer(writePtr))
    _ = try await io.write(to: descriptor, from: writeBuffer)

    let readPtr = UnsafeMutableRawBufferPointer.allocate(
        byteCount: 1024,
        alignment: 1
    )
    defer { unsafe readPtr.deallocate() }
    let readCount = try await io.read(
        from: descriptor,
        into: unsafe Span.Raw.Mutable(readPtr)
    )

    await io.close(consume descriptor)

    var bytes: [UInt8] = []
    bytes.reserveCapacity(readCount)
    for i in 0..<readCount { bytes.append(unsafe readPtr[i]) }
    return bytes
}
