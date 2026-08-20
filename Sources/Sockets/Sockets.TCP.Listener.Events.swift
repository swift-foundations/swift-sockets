//
//  Sockets.TCP.Listener.Events.swift
//  swift-sockets
//

#if !os(Windows)

    internal import IO
    internal import Kernel

    extension Sockets.TCP.Listener {
        /// Event-backed implementation of the listener domain witness.
        internal final class Events: Strategy, Sendable {
            internal let actor: Kernel.Event.Actor
            internal let owner: Sockets.Event.Owner?

            internal init(
                actor: Kernel.Event.Actor,
                owner: Sockets.Event.Owner?
            ) {
                self.actor = actor
                self.owner = owner
            }

            internal var executor: UnownedSerialExecutor {
                unsafe actor.unownedExecutor
            }

            internal func enlist(
                borrowing descriptor: borrowing Kernel.Descriptor
            ) throws(Sockets.Error) -> (
                operation: IO<Sockets.TCP.Listener.Capabilities>.Operation<
                    Sockets.TCP.Accepted,
                    Sockets.Error
                >,
                completion: IO<Sockets.TCP.Listener.Capabilities>.Completion
            ) {
                let actor: Kernel.Event.Actor
                if let owner {
                    actor = try owner.snapshot()
                } else {
                    actor = self.actor
                }
                let enlisted:
                    (
                        operation: IO<Sockets.TCP.Listener.Capabilities>.Operation<
                            Sockets.TCP.Accepted,
                            Event.Wait.Error<Kernel.Socket.Error>
                        >,
                        completion: IO<Sockets.TCP.Listener.Capabilities>.Completion
                    )
                do throws(Kernel.Event.Failure) {
                    enlisted = try actor.enlist(
                        borrowing: descriptor,
                        interest: .read,
                        operation: { descriptor throws(Kernel.Socket.Error) in
                            let result = try POSIX.Kernel.Socket.Accept.accept(descriptor)
                            return Sockets.TCP.Accepted(
                                descriptor: consume result.descriptor,
                                peer: result.address
                            )
                        }
                    )
                } catch {
                    throw Sockets.Error(error)
                }

                let mapped = IO<Sockets.TCP.Listener.Capabilities>.Operation.start(
                    cancellation: enlisted.operation.cancellation,
                    result: {
                        do throws(Event.Wait.Error<Kernel.Socket.Error>) {
                            return try await enlisted.operation.result()
                        } catch {
                            throw Sockets.Error(error)
                        }
                    },
                    completion: {
                        await enlisted.completion.wait()
                    }
                )
                return (consume mapped.operation, consume mapped.completion)
            }

            internal func close(_ descriptor: consuming Kernel.Descriptor) async {
                if let owner {
                    guard let actor = owner.optional() else {
                        Sockets.Event.close(consume descriptor)
                        return
                    }
                    await actor.close(consume descriptor)
                    return
                }
                await actor.close(consume descriptor)
            }

            internal func shutdown() async {
                guard let owner else { return }
                await owner.shutdown()
            }
        }
    }

#endif
