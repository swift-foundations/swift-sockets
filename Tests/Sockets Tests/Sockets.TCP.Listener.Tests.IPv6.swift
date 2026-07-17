//
//  Sockets.TCP.Listener.Tests.IPv6.swift
//  swift-sockets
//
//  Integration test: single TCP connection echoed round-trip over the IPv6
//  loopback (::1), through the IPv6 Listener + Connection.connect factories.
//  Parameterized over the IO strategy matrix.
//
//  NOTE: relies on an available IPv6 loopback. Standard on macOS and Linux;
//  a container/CI host with IPv6 disabled fails socket creation / bind with
//  EAFNOSUPPORT / EADDRNOTAVAIL. Guard to a platform if a gate host lacks
//  ::1.
//

import IO
import Kernel
import Sockets
import Span_Raw_Primitives
import Testing

extension Sockets.TCP.Listener.Tests {
    @Suite
    struct `Sockets.TCP.Listener — IPv6 echo` {}
}

extension Sockets.TCP.Listener.Tests.IPv6 {

    @Test(
        arguments: Sockets.TCP.Listener.Tests.Strategy.allCases
    )
    func `single connection echoes payload round-trip over ::1 per IO strategy`(strategy: Sockets.TCP.Listener.Tests.Strategy) async throws {
        let (_, listener) = try await makeIPv6Server(strategy)
        let clientIO = strategy.makeIO()
        let port = try await listener.port()

        let payload: [UInt8] = [0x01, 0x23, 0x45, 0x67, 0x89]

        async let serverEchoed: [UInt8] = serverSideEcho(listener: listener)
        async let clientReceived: [UInt8] = clientSideRoundTrip(
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

/// Construct an IPv6 server `IO` + `Listener` pair for the strategy, bound
/// to the IPv6 loopback (::1) on a kernel-assigned ephemeral port.
private func makeIPv6Server(
    _ strategy: Sockets.TCP.Listener.Tests.Strategy
) async throws -> (IO<Sockets.Capabilities>, Sockets.TCP.Listener) {
    let io = strategy.makeIO()
    let listener: Sockets.TCP.Listener
    switch strategy {
    case .blocking:
        listener = try Sockets.TCP.Listener.blocking(
            address: Kernel.Socket.Address.IPv6.loopback(port: 0),
            io: io
        )
    case .reactive:
        listener = try Sockets.TCP.Listener.reactive(
            address: Kernel.Socket.Address.IPv6.loopback(port: 0),
            io: io
        )
    }
    return (io, listener)
}

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

// Client-side: connect to ::1 on `port` via Sockets.TCP.Connection.connect
// (IPv6 overload), write the payload, read the echo, close.

private func clientSideRoundTrip(
    io: IO<Sockets.Capabilities>,
    port: UInt16,
    payload: [UInt8]
) async throws -> [UInt8] {
    let connection = try await Sockets.TCP.Connection.connect(
        to: Kernel.Socket.Address.IPv6.loopback(port: port),
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
