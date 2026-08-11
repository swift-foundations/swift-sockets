//
//  Sockets.TCP.Accepted.swift
//  swift-sockets
//

public import Kernel

extension Sockets.TCP {
    /// The move-only result of one listener accept operation.
    ///
    /// Sockets owns this value because it couples the accepted socket
    /// descriptor with the peer address reported by the socket domain. The
    /// sole operation-result owner either transfers it into a ``Connection``
    /// or drops it, closing the descriptor through Kernel ownership.
    public struct Accepted: ~Copyable, Sendable {
        public let descriptor: Kernel.Descriptor
        public let peer: Kernel.Socket.Address.Storage

        package init(
            descriptor: consuming Kernel.Descriptor,
            peer: Kernel.Socket.Address.Storage
        ) {
            self.descriptor = descriptor
            self.peer = peer
        }
    }
}
