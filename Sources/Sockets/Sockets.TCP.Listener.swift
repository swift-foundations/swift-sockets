//
//  Sockets.TCP.Listener.swift
//  swift-sockets
//

public import IO
public import Kernel

extension Sockets.TCP {
    /// A TCP listener with cancellable, physically joined acceptance.
    ///
    /// The listener owns its descriptor and one dedicated
    /// `IO<Sockets.TCP.Listener.Capabilities>`. Acceptance publishes the
    /// lower Cancellation and linear Completion before the actor can suspend.
    /// ``release()`` rejects new acceptance, cancels the live operation, waits
    /// for physical completion, and only then closes the descriptor.
    /// Dropping the actor remains a synchronous fallback: its optional Kernel
    /// descriptor closes through Kernel ownership. An active actor method
    /// retains the actor until its linear operation lifecycle is discharged.
    public actor Listener {
        internal var _descriptor: Kernel.Descriptor?
        internal let _listenerIO: IO<Sockets.TCP.Listener.Capabilities>
        internal let _connectionIO: IO<Sockets.Capabilities>
        internal var _cancellation: IO<Sockets.TCP.Listener.Capabilities>.Cancellation?
        internal var _completion: IO<Sockets.TCP.Listener.Capabilities>.Completion?
        internal var _releasing = false

        internal init(
            descriptor: consuming Kernel.Descriptor,
            listenerIO: IO<Sockets.TCP.Listener.Capabilities>,
            connectionIO: IO<Sockets.Capabilities>
        ) {
            self._descriptor = consume descriptor
            self._listenerIO = listenerIO
            self._connectionIO = connectionIO
        }

        nonisolated public var unownedExecutor: UnownedSerialExecutor {
            unsafe _listenerIO.unownedExecutor
        }
    }
}

extension Sockets.TCP.Listener {
    /// Opens an IPv4 listener. No blocking listener capability is exposed.
    public static func open(
        address: Kernel.Socket.Address.IPv4,
        listenerIO: IO<Sockets.TCP.Listener.Capabilities>,
        connectionIO: IO<Sockets.Capabilities>,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let descriptor = try create(address: address, backlog: backlog)
        try Sockets.Event.prepare(descriptor)
        return .init(
            descriptor: consume descriptor,
            listenerIO: listenerIO,
            connectionIO: connectionIO
        )
    }

    /// Opens an IPv6 listener. No blocking listener capability is exposed.
    public static func open(
        address: Kernel.Socket.Address.IPv6,
        listenerIO: IO<Sockets.TCP.Listener.Capabilities>,
        connectionIO: IO<Sockets.Capabilities>,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let descriptor = try create(address: address, backlog: backlog)
        try Sockets.Event.prepare(descriptor)
        return .init(
            descriptor: consume descriptor,
            listenerIO: listenerIO,
            connectionIO: connectionIO
        )
    }

    private static func create(
        address: Kernel.Socket.Address.IPv4,
        backlog: Kernel.Socket.Backlog
    ) throws(Sockets.Error) -> Kernel.Descriptor {
        do throws(Kernel.Socket.Error) {
            let descriptor = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
            try Kernel.Socket.Bind.bind(descriptor, address: address)
            try Kernel.Socket.Listen.listen(descriptor, backlog: backlog)
            return descriptor
        } catch {
            throw .platform(error.code)
        }
    }

    private static func create(
        address: Kernel.Socket.Address.IPv6,
        backlog: Kernel.Socket.Backlog
    ) throws(Sockets.Error) -> Kernel.Descriptor {
        do throws(Kernel.Socket.Error) {
            let descriptor = try Kernel.Socket.Create.create(domain: .inet6, kind: .stream)
            try Kernel.Socket.Bind.bind(descriptor, address: address)
            try Kernel.Socket.Listen.listen(descriptor, backlog: backlog)
            return descriptor
        } catch {
            throw .platform(error.code)
        }
    }
}

extension Sockets.TCP.Listener {
    /// Accepts one connection on the listener's configured connection IO.
    public func accept() async throws(Sockets.Error) -> Sockets.TCP.Connection {
        try await accept(io: _connectionIO)
    }

    /// Accepts one connection and transfers it to `io`.
    ///
    /// A listener admits at most one accept at a time. This makes the actor the
    /// exact owner of every live Cancellation/Completion pair and gives release
    /// one unambiguous physical-join obligation.
    public func accept(
        io: IO<Sockets.Capabilities>
    ) async throws(Sockets.Error) -> Sockets.TCP.Connection {
        while true {
            guard !_releasing, let descriptor = _descriptor else {
                throw .ioShutdown
            }
            guard _completion == nil else {
                throw .registration(.duplicate)
            }

            let enlisted = try _listenerIO.enlist(borrowing: descriptor)
            _cancellation = enlisted.operation.cancellation
            _completion = consume enlisted.completion

            do throws(Sockets.Error) {
                let accepted = try await enlisted.operation.result()
                _cancellation = nil
                if let completion = _completion.take() {
                    await completion.wait()
                }
                try io.prepare(accepted.descriptor)
                return Sockets.TCP.Connection(
                    descriptor: consume accepted.descriptor,
                    peer: accepted.peer,
                    io: io
                )
            } catch .wouldBlock {
                _cancellation = nil
                if let completion = _completion.take() {
                    await completion.wait()
                }
                continue
            } catch {
                _cancellation = nil
                if let completion = _completion.take() {
                    await completion.wait()
                }
                throw error
            }
        }
    }

    /// Releases the listener without exposing close failures.
    ///
    /// The transition is idempotent. A live accept is cancelled and its
    /// Completion is consumed before the listening descriptor is consumed.
    public func release() async {
        guard !_releasing else { return }
        _releasing = true
        _cancellation?.cancel()
        _cancellation = nil
        if let completion = _completion.take() {
            await completion.wait()
        }
        if let descriptor = _descriptor.take() {
            await _listenerIO.close(consume descriptor)
        }
    }
}

extension Sockets.TCP.Listener {
    /// The bound IPv4/IPv6 port. Calls after release fail closed.
    public func port() throws(Sockets.Error) -> UInt16 {
        guard let descriptor = _descriptor else { throw .ioShutdown }
        do throws(Kernel.Socket.Error) {
            return try Kernel.Socket.Name.local(descriptor).address._port
        } catch {
            throw .platform(error.code)
        }
    }
}
