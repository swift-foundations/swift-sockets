//
//  Sockets.TCP.Listener.Strategy.swift
//  swift-sockets
//

internal import IO
internal import Kernel

extension Sockets.TCP.Listener {
    /// Package-private domain witness implemented only by lawful strategies.
    internal protocol Strategy: Sendable {
        var executor: UnownedSerialExecutor { get }

        func enlist(
            borrowing descriptor: borrowing Kernel.Descriptor
        ) throws(Sockets.Error) -> (
            operation: IO<Sockets.TCP.Listener.Capabilities>.Operation<
                Sockets.TCP.Accepted,
                Sockets.Error
            >,
            completion: IO<Sockets.TCP.Listener.Capabilities>.Completion
        )

        func close(_ descriptor: consuming Kernel.Descriptor) async
        func shutdown() async
    }
}
