public import Executors
public import IO
internal import Thread_Actor

extension IO where Capabilities == Sockets.Capabilities {

    public static func blocking() -> IO<Sockets.Capabilities> {
        blocking(on: _sharedExecutors.next())
    }

    public static func blocking(on executor: Kernel.Thread.Executor) -> IO<Sockets.Capabilities> {
        let actor = Kernel.Thread.Actor(executor: executor)
        let capabilities = Sockets.Capabilities(
            prepare: { _ throws(Sockets.Error) in },
            read: { fd, buffer throws(Sockets.Error) -> Int in
                try await actor.read(from: fd, into: buffer)
            },
            write: { fd, buffer throws(Sockets.Error) -> Int in
                try await actor.write(to: fd, from: buffer)
            },
            close: { fd in
                await actor.close(consume fd)
            },
            ready: { _, _ throws(Sockets.Error) in

            },
            connect: { fd, address, length throws(Sockets.Error) in
                try await actor.connect(fd, to: address, length: length)
            },
            send: { fd, buffer, address, length throws(Sockets.Error) -> Int in
                try await actor.send(on: fd, from: buffer, to: address, length: length)
            },
            receive: { fd, buffer throws(Sockets.Error) in
                try await actor.receive(on: fd, into: buffer)
            }
        )
        let runner = unsafe Self.Runner(
            executor: { unsafe actor.unownedExecutor },
            shutdown: {

            }
        )
        return IO(capabilities: capabilities, runner: runner)
    }
}

private let _sharedExecutors: Kernel.Thread.Executor.Sharded = .init()
