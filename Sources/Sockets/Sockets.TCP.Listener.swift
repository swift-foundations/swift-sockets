public import IO
public import Kernel

extension Sockets.TCP {

    public actor Listener {

        internal let _fd: Kernel.Descriptor

        internal let _io: IO<Sockets.Capabilities>

        internal init(fd: consuming Kernel.Descriptor, io: IO<Sockets.Capabilities>) {
            self._fd = fd
            self._io = io
        }
    }
}

extension Sockets.TCP.Listener {

    nonisolated public var unownedExecutor: UnownedSerialExecutor {
        unsafe _io.unownedExecutor
    }
}

extension Sockets.TCP.Listener {

    public static func blocking(
        address: Kernel.Socket.Address.IPv4,
        io: IO<Sockets.Capabilities>,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let fd = try createBindListen(address: address, backlog: backlog)
        try io.prepare(fd)
        return Sockets.TCP.Listener(fd: consume fd, io: io)
    }

    public static func blocking(
        address: Kernel.Socket.Address.IPv6,
        io: IO<Sockets.Capabilities>,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let fd = try createBindListen(address: address, backlog: backlog)
        try io.prepare(fd)
        return Sockets.TCP.Listener(fd: consume fd, io: io)
    }

    public static func reactive(
        address: Kernel.Socket.Address.IPv4,
        io: IO<Sockets.Capabilities>,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let fd = try createBindListen(address: address, backlog: backlog)
        try io.prepare(fd)
        return Sockets.TCP.Listener(fd: consume fd, io: io)
    }

    public static func reactive(
        address: Kernel.Socket.Address.IPv6,
        io: IO<Sockets.Capabilities>,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let fd = try createBindListen(address: address, backlog: backlog)
        try io.prepare(fd)
        return Sockets.TCP.Listener(fd: consume fd, io: io)
    }

    private static func createBindListen(
        address: Kernel.Socket.Address.IPv4,
        backlog: Kernel.Socket.Backlog
    ) throws(Sockets.Error) -> Kernel.Descriptor {
        do throws(Kernel.Socket.Error) {
            let socket = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
            try Kernel.Socket.Bind.bind(socket, address: address)
            try Kernel.Socket.Listen.listen(socket, backlog: backlog)
            return socket
        } catch {
            throw .platform(error.code)
        }
    }

    private static func createBindListen(
        address: Kernel.Socket.Address.IPv6,
        backlog: Kernel.Socket.Backlog
    ) throws(Sockets.Error) -> Kernel.Descriptor {
        do throws(Kernel.Socket.Error) {
            let socket = try Kernel.Socket.Create.create(domain: .inet6, kind: .stream)
            try Kernel.Socket.Bind.bind(socket, address: address)
            try Kernel.Socket.Listen.listen(socket, backlog: backlog)
            return socket
        } catch {
            throw .platform(error.code)
        }
    }
}

extension Sockets.TCP.Listener {

    public func accept() async throws(Sockets.Error) -> Sockets.TCP.Connection {
        try await accept(io: _io)
    }

    public func accept(
        io: IO<Sockets.Capabilities>
    ) async throws(Sockets.Error) -> Sockets.TCP.Connection {
        while true {
            try await _io.ready(from: _fd, interest: .read)

            let result: ISO_9945.Kernel.Socket.Accept.Result
            do throws(Kernel.Socket.Error) {
                result = try POSIX.Kernel.Socket.Accept.accept(_fd)
            } catch {

                if error.code == .POSIX.EAGAIN {
                    continue
                }
                throw .platform(error.code)
            }

            try io.prepare(result.descriptor)
            let peer = result.address
            return Sockets.TCP.Connection(
                descriptor: consume result.descriptor,
                peer: peer,
                io: io
            )
        }
    }
}

extension Sockets.TCP.Listener {

    public func port() throws(Sockets.Error) -> UInt16 {
        let storage: Kernel.Socket.Address.Storage
        do throws(Kernel.Socket.Error) {
            storage = try Kernel.Socket.Name.local(_fd).address
        } catch {
            throw .platform(error.code)
        }
        return storage._port
    }
}
