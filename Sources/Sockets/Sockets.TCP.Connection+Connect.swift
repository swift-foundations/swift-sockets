public import IO
public import Kernel

extension Sockets.TCP.Connection {

    public static func connect(
        to address: Kernel.Socket.Address.IPv4,
        io: IO<Sockets.Capabilities>
    ) async throws(Sockets.Error) -> sending Sockets.TCP.Connection {
        let socket: Kernel.Descriptor
        do throws(Kernel.Socket.Error) {
            socket = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
        } catch {
            throw Sockets.Error(error)
        }
        try io.prepare(socket)
        try await io.connect(socket, to: address.storage, length: Kernel.Socket.Address.IPv4.size)
        return Sockets.TCP.Connection(descriptor: consume socket, peer: address.storage, io: io)
    }

    public static func connect(
        to address: Kernel.Socket.Address.IPv6,
        io: IO<Sockets.Capabilities>
    ) async throws(Sockets.Error) -> sending Sockets.TCP.Connection {
        let socket: Kernel.Descriptor
        do throws(Kernel.Socket.Error) {
            socket = try Kernel.Socket.Create.create(domain: .inet6, kind: .stream)
        } catch {
            throw Sockets.Error(error)
        }
        try io.prepare(socket)
        try await io.connect(socket, to: address.storage, length: Kernel.Socket.Address.IPv6.size)
        return Sockets.TCP.Connection(descriptor: consume socket, peer: address.storage, io: io)
    }
}

extension Sockets.TCP.Connection {

    package static func connectReactively(
        _ descriptor: borrowing Kernel.Descriptor,
        to address: Kernel.Socket.Address.Storage,
        length: Kernel.Socket.Address.Length,
        ready: (borrowing Kernel.Descriptor, Kernel.Event.Interest) async throws(Sockets.Error) ->
            Void
    ) async throws(Sockets.Error) {

        do throws(Kernel.Socket.Error) {
            try ISO_9945.Kernel.Socket.Connect.connect(descriptor, address: address, length: length)
            return
        } catch {
            let code = error.code
            guard code.isInterrupted || code.isInProgress else {
                throw Sockets.Error(error)
            }
        }

        try await ready(descriptor, .write)

        let pending: Error_Primitives.Error.Code
        do throws(Kernel.Socket.Error) {
            pending = try ISO_9945.Kernel.Socket.getError(descriptor)
        } catch {
            throw Sockets.Error(error)
        }
        guard pending == .posix(0) else {
            throw .platform(pending)
        }
    }

}
