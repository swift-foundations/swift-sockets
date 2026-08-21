import IO
import Kernel
import Sockets
import Span_Raw_Primitives
import Testing

extension Sockets.TCP.Listener.Tests {
    @Suite
    struct `Half Close` {}
}

extension Sockets.TCP.Listener.Tests.`Half Close` {

    @Test(
        arguments: Sockets.TCP.Listener.Tests.Strategy.allCases
    )
    func `half-close echo: shutdown(.write) sends FIN, peer reads EOF per IO strategy`(
        strategy: Sockets.TCP.Listener.Tests.Strategy
    ) async throws {
        let (_, listener) = try await Sockets.TCP.Listener.Tests.Strategy.makeServer(strategy)
        let clientIO = IO<Sockets.Capabilities>.blocking()
        let port = try await listener.port()

        let payload: [UInt8] = [0x48, 0x41, 0x4C, 0x46]

        try await withThrowingDiscardingTaskGroup { group in

            group.addTask {
                let conn = try await listener.accept()

                let buf = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
                defer { unsafe buf.deallocate() }

                let n = try await conn.read(into: unsafe .init(buf))
                #expect(n == payload.count, "Server read the full payload before EOF.")

                let eof = try await conn.read(into: unsafe .init(buf))
                #expect(eof == 0, "Server sees EOF after client shutdown(.write).")

                let echo = unsafe UnsafeRawBufferPointer(start: buf.baseAddress, count: n)
                _ = try await conn.write(from: unsafe .init(echo))

                try conn.shutdown(how: .write)

            }

            group.addTask {
                let socket = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
                try POSIX.Kernel.Socket.Connect.connect(
                    socket,
                    address: Kernel.Socket.Address.IPv4.loopback(port: port)
                )
                let descriptor = consume socket

                let wbuf = UnsafeMutableRawBufferPointer.allocate(
                    byteCount: payload.count,
                    alignment: 1
                )
                defer { unsafe wbuf.deallocate() }
                for (i, b) in payload.enumerated() { unsafe wbuf[i] = b }
                _ = try await clientIO.write(
                    to: descriptor,
                    from: unsafe .init(UnsafeRawBufferPointer(wbuf))
                )

                try Kernel.Socket.Shutdown.shutdown(descriptor, how: .write)

                let rbuf = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
                defer { unsafe rbuf.deallocate() }
                let n = try await clientIO.read(from: descriptor, into: unsafe .init(rbuf))
                #expect(n == payload.count, "Client read the echoed payload.")

                var received: [UInt8] = []
                received.reserveCapacity(n)
                for i in 0..<n { received.append(unsafe rbuf[i]) }
                #expect(received == payload, "Client received its own payload echoed back.")

                let eof = try await clientIO.read(from: descriptor, into: unsafe .init(rbuf))
                #expect(eof == 0, "Client sees EOF after server shutdown(.write).")

                await clientIO.close(consume descriptor)
            }
        }
    }
}
