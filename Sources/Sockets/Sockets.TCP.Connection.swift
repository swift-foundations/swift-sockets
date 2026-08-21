public import IO
public import Kernel
public import Span_Raw_Primitives

extension Sockets.TCP {

    public struct Connection: ~Copyable, Sendable {

        public let descriptor: Kernel.Descriptor

        public let peer: Kernel.Socket.Address.Storage

        public let io: IO<Sockets.Capabilities>

        internal init(
            descriptor: consuming Kernel.Descriptor,
            peer: Kernel.Socket.Address.Storage,
            io: IO<Sockets.Capabilities>
        ) {
            self.descriptor = descriptor
            self.peer = peer
            self.io = io
        }
    }
}

extension Sockets.TCP.Connection {

    public borrowing func read(
        into buffer: Span.Raw.Mutable
    ) async throws(Sockets.Error) -> Int {
        try await io.read(from: descriptor, into: buffer)
    }

    public borrowing func write(
        from buffer: Span.Raw
    ) async throws(Sockets.Error) -> Int {
        try await io.write(to: descriptor, from: buffer)
    }

    public consuming func close() async {
        await io.close(consume descriptor)
    }
}

extension Sockets.TCP.Connection {

    public borrowing func shutdown(
        how: Kernel.Socket.Shutdown.How
    ) throws(Sockets.Error) {
        do throws(Kernel.Socket.Shutdown.Error) {
            try Kernel.Socket.Shutdown.shutdown(descriptor, how: how)
        } catch {
            switch error {
            case .platform(let err): throw .platform(err.code)
            }
        }
    }
}
