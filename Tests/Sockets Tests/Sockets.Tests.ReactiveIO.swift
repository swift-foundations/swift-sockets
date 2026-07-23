//
//  Sockets.Tests.ReactiveIO.swift
//  swift-sockets
//
//  Test-support reactive `IO<Sockets.Capabilities>` factory. Exists ONLY
//  to exercise the reactive (non-blocking + readiness) code paths that
//  the blocking strategy short-circuits: the O_NONBLOCK accept loop, the
//  reactive connect sequence, and the EAGAIN-retry read/write. It is NOT
//  a public reactor factory — the real reactor-backed factories are
//  swift-io's territory (Phase 2B / 2C). Readiness here is a blocking
//  `poll(2)` on the pinned Kernel.Thread.Actor thread; a real reactor
//  would await a kernel readiness event instead.
//

import Executors
import IO
import Kernel
import POSIX_Kernel_Poll
import Sockets
import Span_Raw_Primitives
import Thread_Actor

/// Process-scoped sharded executor pool for the reactive test IOs. Mirrors
/// the blocking factory's process-scoped pool so each reactive IO pins one
/// shard for the process lifetime rather than leaking a fresh thread per
/// test invocation.
private let _reactiveTestExecutors: Kernel.Thread.Executor.Sharded = .init()

/// Builds a reactive-strategy `IO<Sockets.Capabilities>` pinned to a shard
/// of the process-scoped reactive test pool.
///
/// The capability closures forward to reactive bindings on a pinned
/// `Kernel.Thread.Actor`: read/write retry on `EAGAIN` after a poll, the
/// `ready` primitive is a blocking `poll(2)`, and `connect` reuses the
/// Sources ``Sockets/TCP/Connection/connectReactively(_:to:length:ready:)``
/// sequence with this poll as its readiness primitive.
func makeReactiveIO() -> IO<Sockets.Capabilities> {
    let actor = Kernel.Thread.Actor(executor: _reactiveTestExecutors.next())
    let capabilities = Sockets.Capabilities(
        prepare: { fd throws(Sockets.Error) in
            do throws(Kernel.File.Control.Error) {
                try Kernel.File.Control.setNonBlocking(fd)
            } catch {
                switch error {
                case .platform(let value): throw .platform(value.code)
                case .handle(let value): throw .platform(value.code)
                }
            }
        },
        read: { fd, buffer throws(Sockets.Error) -> Int in
            try await actor.testReactiveRead(from: fd, into: buffer)
        },
        write: { fd, buffer throws(Sockets.Error) -> Int in
            try await actor.testReactiveWrite(to: fd, from: buffer)
        },
        close: { fd in
            await actor.testClose(consume fd)
        },
        ready: { fd, interest throws(Sockets.Error) in
            try await actor.testPollReady(fd, interest: interest)
        },
        connect: { fd, address, length throws(Sockets.Error) in
            try await Sockets.TCP.Connection.connectReactively(
                fd,
                to: address,
                length: length,
                ready: { descriptor, interest throws(Sockets.Error) in
                    try await actor.testPollReady(descriptor, interest: interest)
                }
            )
        },
        send: { fd, buffer, address, length throws(Sockets.Error) -> Int in
            try await actor.testReactiveSend(on: fd, from: buffer, to: address, length: length)
        },
        receive: { fd, buffer throws(Sockets.Error) -> (count: Int, peer: Kernel.Socket.Address.Storage, length: Kernel.Socket.Address.Length) in
            try await actor.testReactiveReceive(on: fd, into: buffer)
        }
    )
    let runner = unsafe IO<Sockets.Capabilities>.Runner(
        executor: { unsafe actor.unownedExecutor },
        shutdown: {
            // Shards live for the process lifetime (shared pool); nothing
            // to shut down per IO.
        }
    )
    return IO(capabilities: capabilities, runner: runner)
}

// MARK: - Reactive bindings on the pinned actor
//
// Test-module extensions on Kernel.Thread.Actor — visible only to the
// test target. Each method runs on the actor's pinned thread; the poll
// blocks that thread until the fd is ready, which is the reactive analog
// of the blocking strategy sleeping inside the syscall.

extension Kernel.Thread.Actor {

    /// Reads into `buffer` on the pinned thread, polling for readability
    /// and retrying on `EAGAIN`. Returns bytes read (0 at EOF).
    func testReactiveRead(
        from descriptor: borrowing Kernel.Descriptor,
        into buffer: Span.Raw.Mutable
    ) throws(Sockets.Error) -> Int {
        while true {
            do throws(Kernel.IO.Read.Error) {
                return try unsafe Kernel.IO.Read.read(descriptor, into: unsafe buffer.base.nonNull)
            } catch {
                guard Error_Primitives.Error.Code.POSIX.isEAGAIN(error.code) else {
                    throw .platform(error.code)
                }
            }
            try testPollReady(descriptor, interest: .read)
        }
    }

    /// Writes `buffer` on the pinned thread, polling for writability and
    /// retrying on `EAGAIN`. Returns bytes written.
    func testReactiveWrite(
        to descriptor: borrowing Kernel.Descriptor,
        from buffer: Span.Raw
    ) throws(Sockets.Error) -> Int {
        while true {
            do throws(Kernel.IO.Write.Error) {
                return try unsafe Kernel.IO.Write.write(descriptor, from: unsafe buffer.base.nonNull)
            } catch {
                guard Error_Primitives.Error.Code.POSIX.isEAGAIN(error.code) else {
                    throw .platform(error.code)
                }
            }
            try testPollReady(descriptor, interest: .write)
        }
    }

    /// Sends a datagram on the pinned thread, polling for writability and
    /// retrying on `EAGAIN`. Returns bytes sent.
    func testReactiveSend(
        on descriptor: borrowing Kernel.Descriptor,
        from buffer: Span.Raw,
        to address: Kernel.Socket.Address.Storage,
        length: Kernel.Socket.Address.Length
    ) throws(Sockets.Error) -> Int {
        while true {
            do throws(Kernel.Socket.Error) {
                return try POSIX.Kernel.Socket.Send.to(
                    descriptor,
                    from: buffer.span,
                    address: address,
                    addressLength: length
                )
            } catch {
                guard Error_Primitives.Error.Code.POSIX.isEAGAIN(error.code) else {
                    throw .platform(error.code)
                }
            }
            try testPollReady(descriptor, interest: .write)
        }
    }

    /// Receives a datagram on the pinned thread, polling for readability
    /// and retrying on `EAGAIN`. Returns bytes received and the sender.
    func testReactiveReceive(
        on descriptor: borrowing Kernel.Descriptor,
        into buffer: Span.Raw.Mutable
    ) throws(Sockets.Error) -> (count: Int, peer: Kernel.Socket.Address.Storage, length: Kernel.Socket.Address.Length) {
        var buffer = buffer
        while true {
            do throws(Kernel.Socket.Error) {
                var span = buffer.mutableSpan
                let result = try POSIX.Kernel.Socket.Receive.from(descriptor, into: &span)
                return (count: result.count, peer: result.address, length: result.addressLength)
            } catch {
                guard Error_Primitives.Error.Code.POSIX.isEAGAIN(error.code) else {
                    throw .platform(error.code)
                }
            }
            try testPollReady(descriptor, interest: .read)
        }
    }

    /// Blocks the pinned thread in `poll(2)` until `descriptor` is ready
    /// for the requested interest. The reactive `ready` primitive.
    func testPollReady(
        _ descriptor: borrowing Kernel.Descriptor,
        interest: Kernel.Event.Interest
    ) throws(Sockets.Error) {
        let events: POSIX.Kernel.Poll.Events = interest.contains(.write) ? .output : .input
        var entries = [POSIX.Kernel.Poll.Entry(descriptor, requested: events)]
        do throws(Error_Primitives.Error) {
            _ = try POSIX.Kernel.Poll.poll(&entries, timeout: -1)
        } catch {
            throw .platform(error.code)
        }
    }

    /// Closes `descriptor` on the pinned thread. Close errors are swallowed
    /// (the fd is closed at the kernel level regardless).
    func testClose(_ descriptor: consuming Kernel.Descriptor) {
        do throws(Kernel.Close.Error) {
            try Kernel.Close.close(consume descriptor)
        } catch {
            // fd is already closed — error is informational only.
        }
    }
}
