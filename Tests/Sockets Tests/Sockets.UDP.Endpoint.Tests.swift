import IO
import Kernel
import Sockets
import Span_Raw_Primitives
import Testing

extension Sockets.UDP.Endpoint {

    @Suite(.serialized)
    enum Tests {}
}

extension Sockets.UDP.Endpoint.Tests {
    @Suite
    struct `Sockets.UDP.Endpoint — datagram round-trip` {}
}

extension Sockets.UDP.Endpoint.Tests.`Sockets.UDP.Endpoint — datagram round-trip` {

    @Test
    func `IPv4 datagram round-trips client to server and back to peer`() async throws {
        let serverIO = IO<Sockets.Capabilities>.blocking()
        let clientIO = IO<Sockets.Capabilities>.blocking()
        let server = try Sockets.UDP.Endpoint.bound(
            to: Kernel.Socket.Address.IPv4.loopback(port: 0),
            io: serverIO
        )
        let client = try Sockets.UDP.Endpoint.bound(
            to: Kernel.Socket.Address.IPv4.loopback(port: 0),
            io: clientIO
        )
        let serverPort = try server.port()

        let payload: [UInt8] = [0xD1, 0x5C, 0x0F, 0xFE]

        let sendPtr = UnsafeMutableRawBufferPointer.allocate(byteCount: payload.count, alignment: 1)
        defer { unsafe sendPtr.deallocate() }
        for (i, byte) in payload.enumerated() { unsafe sendPtr[i] = byte }
        let sendSpan: Span.Raw = unsafe .init(UnsafeRawBufferPointer(sendPtr))
        let sent = try await client.send(
            sendSpan,
            to: Kernel.Socket.Address.IPv4.loopback(port: serverPort)
        )
        #expect(sent == payload.count, "Client sent the whole datagram.")

        let recvPtr = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
        defer { unsafe recvPtr.deallocate() }
        let (received, peer, peerLength) = try await server.receive(into: unsafe .init(recvPtr))
        var serverBytes: [UInt8] = []
        serverBytes.reserveCapacity(received)
        for i in 0..<received { serverBytes.append(unsafe recvPtr[i]) }
        #expect(serverBytes == payload, "Server received the datagram the client sent.")
        #expect(peer.family == .inet, "Reported sender address is IPv4.")

        let echoSlice = unsafe UnsafeRawBufferPointer(start: recvPtr.baseAddress, count: received)
        let echoSpan: Span.Raw = unsafe .init(echoSlice)
        let echoed = try await server.send(echoSpan, to: peer, length: peerLength)
        #expect(echoed == payload.count, "Server echoed the whole datagram.")

        let clientRecvPtr = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
        defer { unsafe clientRecvPtr.deallocate() }
        let (echoCount, _, _) = try await client.receive(into: unsafe .init(clientRecvPtr))
        var clientBytes: [UInt8] = []
        clientBytes.reserveCapacity(echoCount)
        for i in 0..<echoCount { clientBytes.append(unsafe clientRecvPtr[i]) }
        #expect(
            clientBytes == payload,
            "Client received its datagram echoed back to its peer address."
        )

        await server.close()
        await client.close()
    }

    @Test
    func `IPv6 datagram round-trips client to server and back to peer over ::1`() async throws {
        let serverIO = IO<Sockets.Capabilities>.blocking()
        let clientIO = IO<Sockets.Capabilities>.blocking()
        let server = try Sockets.UDP.Endpoint.bound(
            to: Kernel.Socket.Address.IPv6.loopback(port: 0),
            io: serverIO
        )
        let client = try Sockets.UDP.Endpoint.bound(
            to: Kernel.Socket.Address.IPv6.loopback(port: 0),
            io: clientIO
        )
        let serverPort = try server.port()

        let payload: [UInt8] = [0xFE, 0xED, 0xC0, 0xDE, 0x06]

        let sendPtr = UnsafeMutableRawBufferPointer.allocate(byteCount: payload.count, alignment: 1)
        defer { unsafe sendPtr.deallocate() }
        for (i, byte) in payload.enumerated() { unsafe sendPtr[i] = byte }
        let sendSpan: Span.Raw = unsafe .init(UnsafeRawBufferPointer(sendPtr))
        let sent = try await client.send(
            sendSpan,
            to: Kernel.Socket.Address.IPv6.loopback(port: serverPort)
        )
        #expect(sent == payload.count, "Client sent the whole datagram.")

        let recvPtr = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
        defer { unsafe recvPtr.deallocate() }
        let (received, peer, peerLength) = try await server.receive(into: unsafe .init(recvPtr))
        var serverBytes: [UInt8] = []
        serverBytes.reserveCapacity(received)
        for i in 0..<received { serverBytes.append(unsafe recvPtr[i]) }
        #expect(serverBytes == payload, "Server received the datagram the client sent.")
        #expect(peer.family == .inet6, "Reported sender address is IPv6.")

        let echoSlice = unsafe UnsafeRawBufferPointer(start: recvPtr.baseAddress, count: received)
        let echoSpan: Span.Raw = unsafe .init(echoSlice)
        let echoed = try await server.send(echoSpan, to: peer, length: peerLength)
        #expect(echoed == payload.count, "Server echoed the whole datagram.")

        let clientRecvPtr = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
        defer { unsafe clientRecvPtr.deallocate() }
        let (echoCount, _, _) = try await client.receive(into: unsafe .init(clientRecvPtr))
        var clientBytes: [UInt8] = []
        clientBytes.reserveCapacity(echoCount)
        for i in 0..<echoCount { clientBytes.append(unsafe clientRecvPtr[i]) }
        #expect(
            clientBytes == payload,
            "Client received its datagram echoed back to its peer address."
        )

        await server.close()
        await client.close()
    }
}
