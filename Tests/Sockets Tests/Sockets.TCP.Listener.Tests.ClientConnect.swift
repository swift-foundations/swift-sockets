//
//  Sockets.TCP.Listener.Tests.ClientConnect.swift
//  swift-sockets
//
//  Integration test: client-side echo round-trip through the
//  Sockets.TCP.Connection.connect factory (replacing the raw inline
//  Kernel.Socket.Connect used by the other suites). Parameterized over the
//  IO strategy matrix — the `.reactive` cell drives the non-blocking
//  connect sequence (O_NONBLOCK → connect → poll(.write) → SO_ERROR) end
//  to end, and the subsequent read/write travel the client's reactive
//  EAGAIN-retry path.
//

import IO
import Kernel
import Sockets
import Span_Raw_Primitives
import Testing

extension Sockets.TCP.Listener.Tests {
    @Suite
    struct `Client Connect` {}
}

extension Sockets.TCP.Listener.Tests.`Client Connect` {

    @Test(
        arguments: Sockets.TCP.Listener.Tests.Strategy.allCases
    )
    func `connect() client echoes payload round-trip per IO strategy`(strategy: Sockets.TCP.Listener.Tests.Strategy) async throws {
        let (_, listener) = try await Sockets.TCP.Listener.Tests.Strategy.makeServer(strategy)
        let clientIO = strategy.makeIO()
        let port = try await listener.port()

        let payload: [UInt8] = [0xC0, 0xDE, 0xF0, 0x0D]

        async let serverEchoed: [UInt8] = serverSideEcho(listener: listener)
        async let clientReceived: [UInt8] = clientConnectRoundTrip(
            io: clientIO,
            port: port,
            payload: payload
        )

        let (server, client) = try await (serverEchoed, clientReceived)

        #expect(server == payload, "Server saw the payload the client sent.")
        #expect(client == payload, "Client saw its own payload echoed back.")
    }
}

// MARK: - Helpers
//
// Server-side accept-and-echo is identical to the Echo suite; duplicated
// rather than hoisted per [PATTERN-026] (tests read top-to-bottom).

private func serverSideEcho(listener: Sockets.TCP.Listener) async throws -> [UInt8] {
    let connection = try await listener.accept()

    let buffer = UnsafeMutableRawBufferPointer.allocate(
        byteCount: 1024,
        alignment: 1
    )
    defer { unsafe buffer.deallocate() }

    let readCount = try await connection.read(
        into: unsafe .init(buffer)
    )

    let payloadSlice = unsafe UnsafeRawBufferPointer(
        start: buffer.baseAddress,
        count: readCount
    )
    _ = try await connection.write(from: unsafe .init(payloadSlice))

    await connection.close()

    var bytes: [UInt8] = []
    bytes.reserveCapacity(readCount)
    for i in 0..<readCount { bytes.append(unsafe buffer[i]) }
    return bytes
}

// Client-side: establish the connection via Sockets.TCP.Connection.connect
// (rather than a raw Kernel.Socket.Connect), write the payload, read the
// echo, close. Returns the bytes received.

private func clientConnectRoundTrip(
    io: IO<Sockets.Capabilities>,
    port: UInt16,
    payload: [UInt8]
) async throws -> [UInt8] {
    let connection = try await Sockets.TCP.Connection.connect(
        to: Kernel.Socket.Address.IPv4.loopback(port: port),
        io: io
    )

    let writePtr = UnsafeMutableRawBufferPointer.allocate(
        byteCount: payload.count,
        alignment: 1
    )
    defer { unsafe writePtr.deallocate() }
    for (i, byte) in payload.enumerated() {
        unsafe writePtr[i] = byte
    }
    _ = try await connection.write(from: unsafe .init(UnsafeRawBufferPointer(writePtr)))

    let readPtr = UnsafeMutableRawBufferPointer.allocate(
        byteCount: 1024,
        alignment: 1
    )
    defer { unsafe readPtr.deallocate() }
    let readCount = try await connection.read(into: unsafe .init(readPtr))

    await connection.close()

    var bytes: [UInt8] = []
    bytes.reserveCapacity(readCount)
    for i in 0..<readCount { bytes.append(unsafe readPtr[i]) }
    return bytes
}
