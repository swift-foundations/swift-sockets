public import Kernel
public import Span_Raw_Primitives

extension Sockets {

    public struct Capabilities: Sendable {

        public let prepare: @Sendable (borrowing Kernel.Descriptor) throws(Sockets.Error) -> Void

        public let read:
            @Sendable (
                borrowing Kernel.Descriptor,
                Span.Raw.Mutable
            ) async throws(Sockets.Error) -> Int

        public let write:
            @Sendable (
                borrowing Kernel.Descriptor,
                Span.Raw
            ) async throws(Sockets.Error) -> Int

        public let close: @Sendable (consuming Kernel.Descriptor) async -> Void

        public let ready:
            @Sendable (
                borrowing Kernel.Descriptor,
                Kernel.Event.Interest
            ) async throws(Sockets.Error) -> Void

        public let connect:
            @Sendable (
                borrowing Kernel.Descriptor,
                Kernel.Socket.Address.Storage,
                Kernel.Socket.Address.Length
            ) async throws(Sockets.Error) -> Void

        public let send:
            @Sendable (
                borrowing Kernel.Descriptor,
                Span.Raw,
                Kernel.Socket.Address.Storage,
                Kernel.Socket.Address.Length
            ) async throws(Sockets.Error) -> Int

        public let receive:
            @Sendable (
                borrowing Kernel.Descriptor,
                Span.Raw.Mutable
            ) async throws(Sockets.Error) -> (
                count: Int,
                peer: Kernel.Socket.Address.Storage,
                length: Kernel.Socket.Address.Length
            )

        public init(
            prepare:
                @Sendable @escaping (
                    borrowing Kernel.Descriptor
                ) throws(Sockets.Error) -> Void,
            read:
                @Sendable @escaping (
                    borrowing Kernel.Descriptor,
                    Span.Raw.Mutable
                ) async throws(Sockets.Error) -> Int,
            write:
                @Sendable @escaping (
                    borrowing Kernel.Descriptor,
                    Span.Raw
                ) async throws(Sockets.Error) -> Int,
            close: @Sendable @escaping (consuming Kernel.Descriptor) async -> Void,
            ready:
                @Sendable @escaping (
                    borrowing Kernel.Descriptor,
                    Kernel.Event.Interest
                ) async throws(Sockets.Error) -> Void,
            connect:
                @Sendable @escaping (
                    borrowing Kernel.Descriptor,
                    Kernel.Socket.Address.Storage,
                    Kernel.Socket.Address.Length
                ) async throws(Sockets.Error) -> Void,
            send:
                @Sendable @escaping (
                    borrowing Kernel.Descriptor,
                    Span.Raw,
                    Kernel.Socket.Address.Storage,
                    Kernel.Socket.Address.Length
                ) async throws(Sockets.Error) -> Int,
            receive:
                @Sendable @escaping (
                    borrowing Kernel.Descriptor,
                    Span.Raw.Mutable
                ) async throws(Sockets.Error) -> (
                    count: Int,
                    peer: Kernel.Socket.Address.Storage,
                    length: Kernel.Socket.Address.Length
                )
        ) {
            self.prepare = prepare
            self.read = read
            self.write = write
            self.close = close
            self.ready = ready
            self.connect = connect
            self.send = send
            self.receive = receive
        }
    }
}
