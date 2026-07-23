//
//  Sockets.TCP.Listener.Tests.AcceptOnDifferentIO.swift
//  swift-sockets
//
//  Regression test for F-002: prior to this fix, `Listener.accept()`
//  unconditionally homed the returned `Sockets.TCP.Connection` on the
//  listener's own `IO` (`io: _io`) — there was no way to bind an accepted
//  connection to a different `IO` than the one the listener itself uses
//  to wait for and accept the next connection. That forces every
//  connection accepted by one listener onto the same dedicated OS thread
//  as the listener's `accept(2)` loop, so an idle/blocked accept or a
//  slow peer starves every other fd and actor job sharing that thread
//  (the head-of-line hazard documented on `Sockets.TCP.Listener` and
//  `Sockets.TCP.Connection`).
//
//  This test proves `accept(io:)` actually routes the returned
//  connection's byte-level I/O through the *supplied* `IO`, not the
//  listener's own `IO`. `Connection` carries no identity token to compare
//  `IO` values structurally, so the discriminating signal is behavioral:
//  wrap a real blocking `IO`'s `read` capability with a marker closure
//  and confirm the marker fires when that wrapped `IO` is passed to
//  `accept(io:)`.
//
//  IO isolation: this test deliberately uses `blocking(on:)` with
//  executors it OWNS (and shuts down) rather than the no-argument
//  `.blocking()` factory. `.blocking()` pins a shard of the
//  process-scoped shared executor pool per call and advances its
//  round-robin cursor — a process-global side effect that shifts every
//  later test's shard assignment and can rotate two must-run-
//  concurrently actors of a later suite onto the same shard (the
//  shard-collision deadlock documented in this target's suite header).
//  Owned executors keep this test's footprint zero.
//

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
    func `accept(io:) homes the accepted connection's byte-level IO on the supplied IO rather than the listener's own IO`() async throws {
        // Owned executors — no shared-pool pins (see file header).
        let listenerExecutor = Kernel.Thread.Executor(mode: .serial)
        let acceptExecutor = Kernel.Thread.Executor(mode: .serial)
        let clientExecutor = Kernel.Thread.Executor(mode: .serial)
        defer {
            listenerExecutor.shutdown()
            acceptExecutor.shutdown()
            clientExecutor.shutdown()
        }

        // Listener's own IO — the accept-loop thread. The marker is never
        // installed here, so if the marker fires, it can only be because
        // the connection actually read through acceptIO's capabilities.
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
            // Server: accept onto a DIFFERENT IO than the listener's own,
            // then read the client's payload.
            group.addTask {
                let connection = try await listener.accept(io: acceptIO)

                let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
                defer { unsafe buffer.deallocate() }

                _ = try await connection.read(into: unsafe .init(buffer))
                await connection.close()
            }

            // Client: connect and write a payload so the server's read
            // unblocks.
            group.addTask {
                let socket = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
                try POSIX.Kernel.Socket.Connect.connect(
                    socket,
                    address: Kernel.Socket.Address.IPv4.loopback(port: port)
                )
                let descriptor = consume socket
                let clientIO = IO<Sockets.Capabilities>.blocking(on: clientExecutor)

                let writeBuffer = UnsafeMutableRawBufferPointer.allocate(byteCount: payload.count, alignment: 1)
                defer { unsafe writeBuffer.deallocate() }
                for (i, byte) in payload.enumerated() { unsafe writeBuffer[i] = byte }
                _ = try await clientIO.write(to: descriptor, from: unsafe .init(UnsafeRawBufferPointer(writeBuffer)))

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

// MARK: - Marker IO wrapper

/// Actor-isolated flag recording whether the wrapped `read` capability fired.
private actor ReadMarker {
    private(set) var wasHit = false
    func hit() { wasHit = true }
}

/// Wraps a real `IO<Sockets.Capabilities>`'s `read` capability with a
/// marker; every other capability and the runner forward unchanged. Used
/// to observe which `IO` value a `Sockets.TCP.Connection` actually
/// delegates through, since `IO` carries no equatable identity.
private func markedIO(wrapping inner: IO<Sockets.Capabilities>, marker: ReadMarker) -> IO<Sockets.Capabilities> {
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
