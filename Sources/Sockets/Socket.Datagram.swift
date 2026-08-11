//
//  Socket.Datagram.swift
//  swift-sockets
//

public import Buffer_Primitives
public import Byte_Primitives
public import Kernel

extension Socket {
    /// One complete datagram and its routing metadata.
    ///
    /// Datagram boundaries are preserved: one `payload` is exactly one UDP
    /// message, never a stream fragment. `source` and `destination` retain the
    /// kernel address storage *and its actual length*, so either IPv4 or IPv6
    /// routing metadata can be forwarded without guessing its family.
    ///
    /// The payload is owned by this `~Copyable` value. Moving a `Datagram`
    /// moves its bytes and route together; dropping it releases only those
    /// values and never a socket descriptor. Descriptor lifetime remains the
    /// responsibility of `Sockets.UDP.Endpoint`.
    public struct Datagram: ~Copyable, Sendable {
        /// A socket address together with the length returned by the kernel.
        public struct Address: Sendable {
            /// Opaque, family-preserving address storage.
            public let storage: Kernel.Socket.Address.Storage

            /// The valid byte length of `storage` for socket syscalls.
            public let length: Kernel.Socket.Address.Length

            /// Creates routing metadata from kernel address values.
            public init(
                storage: Kernel.Socket.Address.Storage,
                length: Kernel.Socket.Address.Length
            ) {
                self.storage = storage
                self.length = length
            }
        }

        /// The single complete message payload.
        public let payload: Buffer.Slice<Byte_Primitives.Byte>

        /// The sending peer, when the receive operation reports one.
        public let source: Socket.Datagram.Address

        /// The intended receiving peer.
        public let destination: Socket.Datagram.Address

        /// Creates one routed datagram without changing message boundaries.
        public init(
            payload: consuming Buffer.Slice<Byte_Primitives.Byte>,
            source: Socket.Datagram.Address,
            destination: Socket.Datagram.Address
        ) {
            self.payload = payload
            self.source = source
            self.destination = destination
        }
    }
}
