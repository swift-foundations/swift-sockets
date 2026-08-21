public import IO
internal import Kernel

extension Sockets.Event {

    internal static func prepare(
        _ descriptor: borrowing Kernel.Descriptor
    ) throws(Sockets.Error) {
        do throws(Kernel.File.Control.Error) {
            try Kernel.File.Control.setNonBlocking(descriptor)
        } catch {
            throw Sockets.Error(error)
        }
    }

    internal static func close(_ descriptor: consuming Kernel.Descriptor) {
        do throws(Kernel.Close.Error) {
            try Kernel.Close.close(consume descriptor)
        } catch {}
    }
}

extension IO where Capabilities == Sockets.Capabilities {

    public static func events(
        on actor: Kernel.Event.Actor
    ) -> IO<Sockets.Capabilities> {
        let capabilities = Sockets.Capabilities(
            prepare: { descriptor throws(Sockets.Error) in
                try Sockets.Event.prepare(descriptor)
            },
            read: { descriptor, buffer throws(Sockets.Error) -> Int in
                do throws(Kernel.Event.Failure) {
                    return try await actor.read(from: descriptor, into: buffer)
                } catch {
                    throw Sockets.Error(error)
                }
            },
            write: { descriptor, buffer throws(Sockets.Error) -> Int in
                do throws(Kernel.Event.Failure) {
                    return try await actor.write(to: descriptor, from: buffer)
                } catch {
                    throw Sockets.Error(error)
                }
            },
            close: { descriptor in
                await actor.close(consume descriptor)
            },
            ready: { descriptor, interest throws(Sockets.Error) in
                do throws(Kernel.Event.Failure) {
                    try await actor.ready(from: descriptor, interest: interest)
                } catch {
                    throw Sockets.Error(error)
                }
            },
            connect: { descriptor, address, length throws(Sockets.Error) in
                try await Sockets.TCP.Connection.connectReactively(
                    descriptor,
                    to: address,
                    length: length,
                    ready: { descriptor, interest throws(Sockets.Error) in
                        do throws(Kernel.Event.Failure) {
                            try await actor.ready(from: descriptor, interest: interest)
                        } catch {
                            throw Sockets.Error(error)
                        }
                    }
                )
            },
            send: { descriptor, buffer, address, length throws(Sockets.Error) -> Int in
                do throws(Kernel.Event.Failure) {
                    return try await actor.send(
                        on: descriptor,
                        from: buffer,
                        to: address,
                        length: length
                    )
                } catch {
                    throw Sockets.Error(error)
                }
            },
            receive: { descriptor, buffer throws(Sockets.Error) in
                do throws(Kernel.Event.Failure) {
                    return try await actor.receive(on: descriptor, into: buffer)
                } catch {
                    throw Sockets.Error(error)
                }
            }
        )
        let runner = unsafe Self.Runner(
            executor: { unsafe actor.unownedExecutor },
            shutdown: {

            }
        )
        return IO(capabilities: capabilities, runner: runner)
    }

    public static func events() throws(Kernel.Event.Failure) -> IO<Sockets.Capabilities> {
        let actor = try Kernel.Event.Actor()
        let owner = Sockets.Event.Owner(actor)
        let capabilities = Sockets.Capabilities(
            prepare: { descriptor throws(Sockets.Error) in
                _ = try owner.snapshot()
                try Sockets.Event.prepare(descriptor)
            },
            read: { descriptor, buffer throws(Sockets.Error) -> Int in
                let actor = try owner.snapshot()
                do throws(Kernel.Event.Failure) {
                    return try await actor.read(from: descriptor, into: buffer)
                } catch {
                    throw Sockets.Error(error)
                }
            },
            write: { descriptor, buffer throws(Sockets.Error) -> Int in
                let actor = try owner.snapshot()
                do throws(Kernel.Event.Failure) {
                    return try await actor.write(to: descriptor, from: buffer)
                } catch {
                    throw Sockets.Error(error)
                }
            },
            close: { descriptor in
                if let actor = owner.optional() {
                    await actor.close(consume descriptor)
                } else {
                    Sockets.Event.close(consume descriptor)
                }
            },
            ready: { descriptor, interest throws(Sockets.Error) in
                let actor = try owner.snapshot()
                do throws(Kernel.Event.Failure) {
                    try await actor.ready(from: descriptor, interest: interest)
                } catch {
                    throw Sockets.Error(error)
                }
            },
            connect: { descriptor, address, length throws(Sockets.Error) in
                let actor = try owner.snapshot()
                try await Sockets.TCP.Connection.connectReactively(
                    descriptor,
                    to: address,
                    length: length,
                    ready: { descriptor, interest throws(Sockets.Error) in
                        do throws(Kernel.Event.Failure) {
                            try await actor.ready(from: descriptor, interest: interest)
                        } catch {
                            throw Sockets.Error(error)
                        }
                    }
                )
            },
            send: { descriptor, buffer, address, length throws(Sockets.Error) -> Int in
                let actor = try owner.snapshot()
                do throws(Kernel.Event.Failure) {
                    return try await actor.send(
                        on: descriptor,
                        from: buffer,
                        to: address,
                        length: length
                    )
                } catch {
                    throw Sockets.Error(error)
                }
            },
            receive: { descriptor, buffer throws(Sockets.Error) in
                let actor = try owner.snapshot()
                do throws(Kernel.Event.Failure) {
                    return try await actor.receive(on: descriptor, into: buffer)
                } catch {
                    throw Sockets.Error(error)
                }
            }
        )
        let runner = unsafe Self.Runner(
            executor: { unsafe owner.executor },
            shutdown: {
                await owner.shutdown()
            }
        )
        return IO(capabilities: capabilities, runner: runner)
    }
}
