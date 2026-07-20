//
//  Sockets.UDP.Endpoint.Tests.swift
//  swift-sockets
//
//  Integration tests: UDP datagram round-trip through Sockets.UDP.Endpoint
//  over the IPv4 and IPv6 loopbacks. Blocking strategy — a datagram sent to
//  a bound endpoint queues in the kernel socket buffer, so send-then-receive
//  runs sequentially in one task without concurrency (and without the
//  ~Copyable-across-`async let` compiler limitation).
//
//  Each test proves the full path: bind two endpoints on ephemeral ports,
//  send client → server, verify the payload and the reported sender family,
//  echo the datagram back to the captured peer, and verify the client
//  receives its own bytes — a behavioral check that the peer address the
//  server captured routes back to the sender.
//
//  NOTE: the IPv6 test relies on an available ::1 loopback (see the IPv6
//  TCP suite's note).
//

import IO
import Kernel
import Sockets
import Span_Raw_Primitives
import Testing

extension Sockets.UDP.Endpoint {
    /// Test-only namespace grouping integration tests for
    /// ``Sockets/UDP/Endpoint``.
    ///
    /// `.serialized` for the same reason as the TCP suites: each test pins
    /// server + client `IO<Sockets.Capabilities>` values to shards of the
    /// process-scoped blocking-executor pool, and a blocking `recvfrom`
    /// holding its shard while a sibling test needs it would deadlock the
    /// finite pool.
    @Suite(.serialized)
    enum Tests {}
}

extension Sockets.UDP.Endpoint.Tests {
    @Suite
    struct `Sockets.UDP.Endpoint — datagram round-trip` {}
}

extension Sockets.UDP.Endpoint.Tests.RoundTrip {

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

        // 1. Client → server.
        let sendPtr = UnsafeMutableRawBufferPointer.allocate(byteCount: payload.count, alignment: 1)
        defer { unsafe sendPtr.deallocate() }
        for (i, byte) in payload.enumerated() { unsafe sendPtr[i] = byte }
        let sendSpan: Span.Raw = unsafe .init(UnsafeRawBufferPointer(sendPtr))
        let sent = try await client.send(
            sendSpan,
            to: Kernel.Socket.Address.IPv4.loopback(port: serverPort)
        )
        #expect(sent == payload.count, "Client sent the whole datagram.")

        // 2. Server receives, capturing the sender.
        let recvPtr = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
        defer { unsafe recvPtr.deallocate() }
        let (received, peer, peerLength) = try await server.receive(into: unsafe .init(recvPtr))
        var serverBytes: [UInt8] = []
        serverBytes.reserveCapacity(received)
        for i in 0..<received { serverBytes.append(unsafe recvPtr[i]) }
        #expect(serverBytes == payload, "Server received the datagram the client sent.")
        #expect(peer.family == .inet, "Reported sender address is IPv4.")

        // 3. Server echoes back to the captured peer.
        let echoSlice = unsafe UnsafeRawBufferPointer(start: recvPtr.baseAddress, count: received)
        let echoSpan: Span.Raw = unsafe .init(echoSlice)
        let echoed = try await server.send(echoSpan, to: peer, length: peerLength)
        #expect(echoed == payload.count, "Server echoed the whole datagram.")

        // 4. Client receives the echo — confirms the peer address routed back.
        let clientRecvPtr = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
        defer { unsafe clientRecvPtr.deallocate() }
        let (echoCount, _, _) = try await client.receive(into: unsafe .init(clientRecvPtr))
        var clientBytes: [UInt8] = []
        clientBytes.reserveCapacity(echoCount)
        for i in 0..<echoCount { clientBytes.append(unsafe clientRecvPtr[i]) }
        #expect(clientBytes == payload, "Client received its datagram echoed back to its peer address.")

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

        // 1. Client → server.
        let sendPtr = UnsafeMutableRawBufferPointer.allocate(byteCount: payload.count, alignment: 1)
        defer { unsafe sendPtr.deallocate() }
        for (i, byte) in payload.enumerated() { unsafe sendPtr[i] = byte }
        let sendSpan: Span.Raw = unsafe .init(UnsafeRawBufferPointer(sendPtr))
        let sent = try await client.send(
            sendSpan,
            to: Kernel.Socket.Address.IPv6.loopback(port: serverPort)
        )
        #expect(sent == payload.count, "Client sent the whole datagram.")

        // 2. Server receives, capturing the sender.
        let recvPtr = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
        defer { unsafe recvPtr.deallocate() }
        let (received, peer, peerLength) = try await server.receive(into: unsafe .init(recvPtr))
        var serverBytes: [UInt8] = []
        serverBytes.reserveCapacity(received)
        for i in 0..<received { serverBytes.append(unsafe recvPtr[i]) }
        #expect(serverBytes == payload, "Server received the datagram the client sent.")
        #expect(peer.family == .inet6, "Reported sender address is IPv6.")

        // 3. Server echoes back to the captured peer.
        let echoSlice = unsafe UnsafeRawBufferPointer(start: recvPtr.baseAddress, count: received)
        let echoSpan: Span.Raw = unsafe .init(echoSlice)
        let echoed = try await server.send(echoSpan, to: peer, length: peerLength)
        #expect(echoed == payload.count, "Server echoed the whole datagram.")

        // 4. Client receives the echo — confirms the peer address routed back.
        let clientRecvPtr = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
        defer { unsafe clientRecvPtr.deallocate() }
        let (echoCount, _, _) = try await client.receive(into: unsafe .init(clientRecvPtr))
        var clientBytes: [UInt8] = []
        clientBytes.reserveCapacity(echoCount)
        for i in 0..<echoCount { clientBytes.append(unsafe clientRecvPtr[i]) }
        #expect(clientBytes == payload, "Client received its datagram echoed back to its peer address.")

        await server.close()
        await client.close()
    }
}
