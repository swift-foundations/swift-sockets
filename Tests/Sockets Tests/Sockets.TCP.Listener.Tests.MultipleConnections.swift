import IO
import Kernel
import Sockets
import Span_Raw_Primitives
import Testing

extension Sockets.TCP.Listener.Tests {
    @Suite
    struct `Multiple Connections` {}
}

extension Sockets.TCP.Listener.Tests.`Multiple Connections` {

    @Test(
        arguments: Sockets.TCP.Listener.Tests.Strategy.allCases
    )
    func `three concurrent connections echoed correctly round-trip per IO strategy`(
        strategy: Sockets.TCP.Listener.Tests.Strategy
    ) async throws {
        let (_, listener) = try await Sockets.TCP.Listener.Tests.Strategy.makeServer(strategy)
        let clientIO = IO<Sockets.Capabilities>.blocking()
        let port = try await listener.port()

        let payloads: [[UInt8]] = [
            [0x11, 0x22, 0x33],
            [0xAA, 0xBB, 0xCC],
            [0xF0, 0xE1, 0xD2],
        ]

        async let server0: [UInt8] = serverSideEcho(listener: listener)
        async let server1: [UInt8] = serverSideEcho(listener: listener)
        async let server2: [UInt8] = serverSideEcho(listener: listener)

        async let client0: [UInt8] = clientSideRoundTrip(
            io: clientIO,
            port: port,
            payload: payloads[0]
        )
        async let client1: [UInt8] = clientSideRoundTrip(
            io: clientIO,
            port: port,
            payload: payloads[1]
        )
        async let client2: [UInt8] = clientSideRoundTrip(
            io: clientIO,
            port: port,
            payload: payloads[2]
        )

        let (s0, s1, s2) = try await (server0, server1, server2)
        let (c0, c1, c2) = try await (client0, client1, client2)

        let serverEchoes = [s0, s1, s2]
        let clientReceives = [c0, c1, c2]

        #expect(
            Set(clientReceives) == Set(payloads),
            "Each client sees its own payload echoed back (order may differ by scheduling)."
        )

        #expect(
            Set(serverEchoes) == Set(payloads),
            "Server saw every payload exactly once across the three accepts."
        )
    }
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

private func clientSideRoundTrip(
    io: IO<Sockets.Capabilities>,
    port: UInt16,
    payload: [UInt8]
) async throws -> [UInt8] {
    let socket = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
    try POSIX.Kernel.Socket.Connect.connect(
        socket,
        address: Kernel.Socket.Address.IPv4.loopback(port: port)
    )
    let descriptor = consume socket

    let writePtr = UnsafeMutableRawBufferPointer.allocate(
        byteCount: payload.count,
        alignment: 1
    )
    defer { unsafe writePtr.deallocate() }
    for (i, byte) in payload.enumerated() {
        unsafe writePtr[i] = byte
    }
    let writeBuffer: Span.Raw = unsafe .init(UnsafeRawBufferPointer(writePtr))
    _ = try await io.write(to: descriptor, from: writeBuffer)

    let readPtr = UnsafeMutableRawBufferPointer.allocate(
        byteCount: 1024,
        alignment: 1
    )
    defer { unsafe readPtr.deallocate() }
    let readCount = try await io.read(
        from: descriptor,
        into: unsafe .init(readPtr)
    )

    await io.close(consume descriptor)

    var bytes: [UInt8] = []
    bytes.reserveCapacity(readCount)
    for i in 0..<readCount { bytes.append(unsafe readPtr[i]) }
    return bytes
}
