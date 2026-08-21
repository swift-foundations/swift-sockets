public import IO
public import Kernel
public import Span_Raw_Primitives

extension Sockets.UDP {

    public struct Endpoint: ~Copyable, Sendable {

        public let descriptor: Kernel.Descriptor

        public let io: IO<Sockets.Capabilities>

        internal init(
            descriptor: consuming Kernel.Descriptor,
            io: IO<Sockets.Capabilities>
        ) {
            self.descriptor = descriptor
            self.io = io
        }
    }
}

extension Sockets.UDP.Endpoint {

    public static func bound(
        to address: Kernel.Socket.Address.IPv4,
        io: IO<Sockets.Capabilities>
    ) throws(Sockets.Error) -> Sockets.UDP.Endpoint {
        let fd = try createBind(address: address)
        try io.prepare(fd)
        return Sockets.UDP.Endpoint(descriptor: consume fd, io: io)
    }

    public static func bound(
        to address: Kernel.Socket.Address.IPv6,
        io: IO<Sockets.Capabilities>
    ) throws(Sockets.Error) -> Sockets.UDP.Endpoint {
        let fd = try createBind(address: address)
        try io.prepare(fd)
        return Sockets.UDP.Endpoint(descriptor: consume fd, io: io)
    }

    private static func createBind(
        address: Kernel.Socket.Address.IPv4
    ) throws(Sockets.Error) -> Kernel.Descriptor {
        do throws(Kernel.Socket.Error) {
            let socket = try Kernel.Socket.Create.create(domain: .inet, kind: .datagram)
            try Kernel.Socket.Bind.bind(socket, address: address)
            return socket
        } catch {
            throw .platform(error.code)
        }
    }

    private static func createBind(
        address: Kernel.Socket.Address.IPv6
    ) throws(Sockets.Error) -> Kernel.Descriptor {
        do throws(Kernel.Socket.Error) {
            let socket = try Kernel.Socket.Create.create(domain: .inet6, kind: .datagram)
            try Kernel.Socket.Bind.bind(socket, address: address)
            return socket
        } catch {
            throw .platform(error.code)
        }
    }
}

extension Sockets.UDP.Endpoint {

    public borrowing func send(
        _ buffer: Span.Raw,
        to peer: Kernel.Socket.Address.Storage,
        length: Kernel.Socket.Address.Length
    ) async throws(Sockets.Error) -> Int {
        try await io.send(on: descriptor, from: buffer, to: peer, length: length)
    }

    public borrowing func send(
        _ buffer: Span.Raw,
        to address: Kernel.Socket.Address.IPv4
    ) async throws(Sockets.Error) -> Int {
        try await send(buffer, to: address.storage, length: Kernel.Socket.Address.IPv4.size)
    }

    public borrowing func send(
        _ buffer: Span.Raw,
        to address: Kernel.Socket.Address.IPv6
    ) async throws(Sockets.Error) -> Int {
        try await send(buffer, to: address.storage, length: Kernel.Socket.Address.IPv6.size)
    }

    public borrowing func receive(
        into buffer: Span.Raw.Mutable
    ) async throws(Sockets.Error) -> (
        count: Int, peer: Kernel.Socket.Address.Storage, length: Kernel.Socket.Address.Length
    ) {
        try await io.receive(on: descriptor, into: buffer)
    }

    public consuming func close() async {
        await io.close(consume descriptor)
    }
}

extension Sockets.UDP.Endpoint {

    public borrowing func port() throws(Sockets.Error) -> UInt16 {
        let storage: Kernel.Socket.Address.Storage
        do throws(Kernel.Socket.Error) {
            storage = try Kernel.Socket.Name.local(descriptor).address
        } catch {
            throw .platform(error.code)
        }
        return storage._port
    }
}
