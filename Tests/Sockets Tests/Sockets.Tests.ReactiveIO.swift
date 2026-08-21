import Executors
import IO
import Kernel
import POSIX_Kernel_Poll
import Sockets
import Span_Raw_Primitives
import Thread_Actor

private let _reactiveTestExecutors: Kernel.Thread.Executor.Sharded = .init()

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
        receive: {
            fd,
            buffer throws(Sockets.Error) -> (
                count: Int, peer: Kernel.Socket.Address.Storage,
                length: Kernel.Socket.Address.Length
            ) in
            try await actor.testReactiveReceive(on: fd, into: buffer)
        }
    )
    let runner = unsafe IO<Sockets.Capabilities>.Runner(
        executor: { unsafe actor.unownedExecutor },
        shutdown: {

        }
    )
    return IO(capabilities: capabilities, runner: runner)
}

extension Kernel.Thread.Actor {

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

    func testReactiveWrite(
        to descriptor: borrowing Kernel.Descriptor,
        from buffer: Span.Raw
    ) throws(Sockets.Error) -> Int {
        while true {
            do throws(Kernel.IO.Write.Error) {
                return try unsafe Kernel.IO.Write.write(
                    descriptor,
                    from: unsafe buffer.base.nonNull
                )
            } catch {
                guard Error_Primitives.Error.Code.POSIX.isEAGAIN(error.code) else {
                    throw .platform(error.code)
                }
            }
            try testPollReady(descriptor, interest: .write)
        }
    }

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

    func testReactiveReceive(
        on descriptor: borrowing Kernel.Descriptor,
        into buffer: Span.Raw.Mutable
    ) throws(Sockets.Error) -> (
        count: Int, peer: Kernel.Socket.Address.Storage, length: Kernel.Socket.Address.Length
    ) {
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

    func testClose(_ descriptor: consuming Kernel.Descriptor) {
        do throws(Kernel.Close.Error) {
            try Kernel.Close.close(consume descriptor)
        } catch {

        }
    }
}
