import IO
import Kernel
import Sockets
import Span_Raw_Primitives
import Testing

extension Sockets.TCP.Listener.Tests {
    @Suite
    struct `Sockets.TCP.Listener — single connection echo` {}
}

extension Sockets.TCP.Listener.Tests.`Sockets.TCP.Listener — single connection echo` {

    @Test(
        arguments: Sockets.TCP.Listener.Tests.Strategy.allCases
    )
    func `single connection echoes payload round-trip per IO strategy`(
        strategy: Sockets.TCP.Listener.Tests.Strategy
    ) async throws {
        let (_, listener) = try await Sockets.TCP.Listener.Tests.Strategy.makeServer(strategy)
        let clientIO = IO<Sockets.Capabilities>.blocking()
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
