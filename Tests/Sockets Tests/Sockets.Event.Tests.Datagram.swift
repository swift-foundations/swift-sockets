//
//  Sockets.Event.Tests.Datagram.swift
//  swift-sockets
//

import IO
import Kernel
import Span_Raw_Primitives
import Testing

@testable import Sockets

extension Sockets.Event.Tests {
    @Test
    func `event UDP preserves payload and exact sender identity`() async {
        let io: IO<Sockets.Capabilities>
        do throws(Kernel.Event.Failure) {
            io = try .events()
        } catch {
            Issue.record("Owned events factory unavailable: \(error)")
            return
        }

        do throws(Sockets.Error) {
            let server = try Sockets.UDP.Endpoint.bound(
                to: Kernel.Socket.Address.IPv4.loopback(port: 0),
                io: io
            )
            let client = try Sockets.UDP.Endpoint.bound(
                to: Kernel.Socket.Address.IPv4.loopback(port: 0),
                io: io
            )
            let serverPort = try server.port()
            let clientPort = try client.port()
            let payload: [UInt8] = [0xd1, 0x5c, 0x0f, 0xfe]

            let send = UnsafeMutableRawBufferPointer.allocate(byteCount: payload.count, alignment: 1)
            defer { unsafe send.deallocate() }
            for (index, byte) in payload.enumerated() {
                unsafe send[index] = byte
            }
            let sent = try await client.send(
                unsafe .init(UnsafeRawBufferPointer(send)),
                to: Kernel.Socket.Address.IPv4.loopback(port: serverPort)
            )
            #expect(sent == payload.count)

            let receive = UnsafeMutableRawBufferPointer.allocate(byteCount: 64, alignment: 1)
            defer { unsafe receive.deallocate() }
            let result = try await server.receive(into: unsafe .init(receive))
            #expect(result.count == payload.count)
            #expect(result.peer.family == .inet)
            #expect(result.peer._port == clientPort)
            (0..<result.count).forEach { index in
                #expect(unsafe receive[index] == payload[index])
            }

            await server.close()
            await client.close()
        } catch {
            Issue.record("Datagram fixture failed: \(error)")
        }

        await io.runner.shutdown()
    }
}
