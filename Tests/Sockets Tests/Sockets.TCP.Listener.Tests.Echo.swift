//
//  Sockets.TCP.Listener.Tests.Echo.swift
//  swift-sockets
//
//  Integration test: single TCP connection echoed round-trip through a
//  Sockets.TCP.Listener. Validates the TCA26 shared-executor composition
//  end-to-end — the listener forwards its unownedExecutor to the IO's, and
//  accept + read + write + close all run on the IO's dedicated thread via
//  actor isolation.
//

import Testing
import Kernel
import Memory_Primitives
import IO
import Sockets

extension Sockets.TCP.Listener.Tests {
    @Suite("Sockets.TCP.Listener — single connection echo")
    struct Echo {}
}

extension Sockets.TCP.Listener.Tests.Echo {

    @Test("single connection echoes payload round-trip")
    func singleConnection() async throws {
        let serverIO = IO.blocking()
        let clientIO = IO.blocking()
        let listener = try Sockets.TCP.Listener(
            address: .loopback(port: 0),
            io: serverIO
        )
        let port = try await listener.port()

        let payload: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE]

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
//
// Server-side: accept one connection, read up to 1 KiB, echo it back,
// close. Returns the bytes the server read (which are also what it wrote
// back).

private func serverSideEcho(listener: Sockets.TCP.Listener) async throws -> [UInt8] {
    let connection = try await listener.accept()

    let buffer = UnsafeMutableRawBufferPointer.allocate(
        byteCount: 1024,
        alignment: 1
    )
    defer { unsafe buffer.deallocate() }

    let readCount = try await connection.read(
        into: unsafe Memory.Buffer.Mutable(buffer)
    )

    let payloadSlice = unsafe UnsafeRawBufferPointer(
        start: buffer.baseAddress,
        count: readCount
    )
    _ = try await connection.write(from: unsafe Memory.Buffer(payloadSlice))

    await connection.close()

    var bytes: [UInt8] = []
    bytes.reserveCapacity(readCount)
    for i in 0..<readCount { bytes.append(unsafe buffer[i]) }
    return bytes
}

// Client-side: create a TCP socket, connect to 127.0.0.1:port, write
// the payload, read back the echo, close. Returns the bytes received.

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
    let writeBuffer = unsafe Memory.Buffer(UnsafeRawBufferPointer(writePtr))
    _ = try await io.write(to: descriptor, from: writeBuffer)

    let readPtr = UnsafeMutableRawBufferPointer.allocate(
        byteCount: 1024,
        alignment: 1
    )
    defer { unsafe readPtr.deallocate() }
    let readCount = try await io.read(
        from: descriptor,
        into: unsafe Memory.Buffer.Mutable(readPtr)
    )

    await io.close(consume descriptor)

    var bytes: [UInt8] = []
    bytes.reserveCapacity(readCount)
    for i in 0..<readCount { bytes.append(unsafe readPtr[i]) }
    return bytes
}
