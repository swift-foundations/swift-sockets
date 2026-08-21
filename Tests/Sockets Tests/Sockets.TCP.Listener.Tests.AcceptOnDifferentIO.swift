import Executors
import IO
import Kernel
import Sockets
import Span_Raw_Primitives
import Testing

extension Sockets.TCP.Listener.Tests {
    @Suite
    struct `Accept On Different IO` {}
}

extension Sockets.TCP.Listener.Tests.`Accept On Different IO` {

    @Test
    func
        `accept(io:) homes the accepted connection's byte-level IO on the supplied IO rather than the listener's own IO`()
        async throws
    {

        let listenerExecutor = Kernel.Thread.Executor(mode: .serial)
        let acceptExecutor = Kernel.Thread.Executor(mode: .serial)
        let clientExecutor = Kernel.Thread.Executor(mode: .serial)
        defer {
            listenerExecutor.shutdown()
            acceptExecutor.shutdown()
            clientExecutor.shutdown()
        }

        let listenerIO = IO<Sockets.Capabilities>.blocking(on: listenerExecutor)
        let listener = try Sockets.TCP.Listener.blocking(
            address: Kernel.Socket.Address.IPv4.loopback(port: 0),
            io: listenerIO
        )
        let port = try await listener.port()

        let marker = ReadMarker()
        let acceptIO = markedIO(wrapping: .blocking(on: acceptExecutor), marker: marker)

        let payload: [UInt8] = [0x41, 0x42, 0x43, 0x44]

        try await withThrowingDiscardingTaskGroup { group in

            group.addTask {
                let connection = try await listener.accept(io: acceptIO)

                let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
                defer { unsafe buffer.deallocate() }

                _ = try await connection.read(into: unsafe .init(buffer))
                await connection.close()
            }

            group.addTask {
                let socket = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
                try POSIX.Kernel.Socket.Connect.connect(
                    socket,
                    address: Kernel.Socket.Address.IPv4.loopback(port: port)
                )
                let descriptor = consume socket
                let clientIO = IO<Sockets.Capabilities>.blocking(on: clientExecutor)

                let writeBuffer = UnsafeMutableRawBufferPointer.allocate(
                    byteCount: payload.count,
                    alignment: 1
                )
                defer { unsafe writeBuffer.deallocate() }
                for (i, byte) in payload.enumerated() { unsafe writeBuffer[i] = byte }
                _ = try await clientIO.write(
                    to: descriptor,
                    from: unsafe .init(UnsafeRawBufferPointer(writeBuffer))
                )

                await clientIO.close(consume descriptor)
            }
        }

        let fired = await marker.wasHit
        #expect(
            fired,
            "accept(io:) must route the accepted connection's capabilities through the explicitly supplied IO, not the listener's own IO."
        )
    }
}

private actor ReadMarker {
    private(set) var wasHit = false
}

extension ReadMarker {
    func hit() { wasHit = true }
}

private func markedIO(
    wrapping inner: IO<Sockets.Capabilities>,
    marker: ReadMarker
) -> IO<Sockets.Capabilities> {
    let capabilities = Sockets.Capabilities(
        prepare: inner.capabilities.prepare,
        read: { fd, buffer throws(Sockets.Error) -> Int in
            await marker.hit()
            return try await inner.capabilities.read(fd, buffer)
        },
        write: inner.capabilities.write,
        close: inner.capabilities.close,
        ready: inner.capabilities.ready,
        connect: inner.capabilities.connect,
        send: inner.capabilities.send,
        receive: inner.capabilities.receive
    )
    return IO(capabilities: capabilities, runner: inner.runner)
}
