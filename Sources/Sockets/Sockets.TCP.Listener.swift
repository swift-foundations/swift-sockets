//
//  Sockets.TCP.Listener.swift
//  swift-sockets
//

public import IO
public import Kernel

extension Sockets.TCP {

    /// TCP listener bound to a local address.
    ///
    /// An actor holding the listening descriptor and an
    /// `IO<Sockets.Capabilities>`. Forwards `unownedExecutor` to
    /// `io.unownedExecutor` so socket syscalls and accept-result
    /// handling run on the `IO`'s dedicated thread (TCA26
    /// shared-executor pattern). Consumers that also forward their own
    /// `unownedExecutor` to this listener elide the per-call hop.
    ///
    /// ## Strategy pairing
    ///
    /// The `IO` strategy establishes the fd's blocking mode through its
    /// one-shot `prepare` capability before the listener is exposed. The
    /// two retained factories document the intended pairing:
    ///
    /// - ``blocking(address:io:backlog:)`` with `.blocking()` — fd stays in kernel blocking
    ///   mode. `accept(2)` sleeps in the kernel until a connection
    ///   arrives. Intended for `io: .blocking()`.
    /// - ``reactive(address:io:backlog:)`` with `.events()` — `io.prepare`
    ///   sets the fd to `O_NONBLOCK`.
    ///   `accept(2)` returns `EAGAIN` when the queue is empty; the
    ///   accept loop awaits `io.ready(from: _fd, interest: .read)`
    ///   before retrying. Intended for the event-backed reactor factory;
    ///   the same preparation seam can serve a future proactor factory.
    ///
    /// The factory name does not independently mutate flags: both factories
    /// delegate configuration to the supplied `io`. Match the documented
    /// name and strategy at the call site.
    ///
    /// ## Head-of-line hazard
    ///
    /// The accept loop (``accept()`` / ``accept(io:)``) waits on `_io`,
    /// the `IO` this listener was constructed with — an idle or slow
    /// `accept(2)` occupies that `IO`'s dedicated OS thread for as long
    /// as it waits. ``accept()`` also *homes* the returned
    /// ``Sockets/TCP/Connection`` on that same `_io`, so by default every
    /// connection this listener accepts shares one thread with the
    /// accept loop itself and with every other connection accepted the
    /// same way — one slow peer or one blocked read/write starves the
    /// listener and every sibling connection's fd.
    ///
    /// Use ``accept(io:)`` to home an accepted connection's byte-level
    /// I/O on a *different* `IO` than the listener's own. The canonical
    /// pattern: listener on its own dedicated `IO`; each accepted
    /// connection (or a small pool of connections) on separate `IO`(s).
    /// This is a local, structural workaround for Phase 2A's blocking
    /// strategy — swift-io's readiness-based strategies (Phase 2B/2C)
    /// resolve the hazard at the root by not dedicating a whole thread
    /// per accept/read/write in the first place.
    ///
    /// ## Lifecycle
    ///
    /// The listener owns its listening descriptor for the actor's
    /// lifetime. The default actor deinit drops the stored
    /// ``Kernel/Descriptor``, whose own deinit closes the underlying
    /// kernel fd automatically.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let io: IO<Sockets.Capabilities> = .blocking()
    /// let listener = try Sockets.TCP.Listener.blocking(
    ///     address: .loopback(port: 0),
    ///     io: io
    /// )
    /// let connection = try await listener.accept()
    /// ```
    public actor Listener {

        internal let _fd: Kernel.Descriptor

        internal let _io: IO<Sockets.Capabilities>

        internal init(fd: consuming Kernel.Descriptor, io: IO<Sockets.Capabilities>) {
            self._fd = fd
            self._io = io
        }
    }
}

// MARK: - Executor

extension Sockets.TCP.Listener {

    nonisolated public var unownedExecutor: UnownedSerialExecutor {
        unsafe _io.unownedExecutor
    }
}

// MARK: - Construction

extension Sockets.TCP.Listener {

    /// Creates a listener using the supplied IO strategy's preparation.
    ///
    /// Intended for `io: .blocking()`, whose `prepare` hook is a no-op and
    /// therefore leaves the new fd in its kernel-default blocking mode.
    /// `accept(2)` sleeps inside the kernel until a connection arrives;
    /// `io.ready(...)` is a no-op
    /// and the subsequent `accept(2)` is the actual wait point (see
    /// ``Sockets/Capabilities/ready``).
    ///
    /// Passing an events-backed IO makes the fd non-blocking because the IO,
    /// not this factory name, owns preparation. Prefer
    /// ``reactive(address:io:backlog:)`` to make that pairing explicit.
    public static func blocking(
        address: Kernel.Socket.Address.IPv4,
        io: IO<Sockets.Capabilities>,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let fd = try createBindListen(address: address, backlog: backlog)
        try io.prepare(fd)
        return Sockets.TCP.Listener(fd: consume fd, io: io)
    }

    /// Creates an IPv6 listener using the supplied IO strategy's preparation.
    ///
    /// The IPv6 companion of the IPv4 `blocking(address:io:backlog:)`
    /// factory; the same strategy pairing applies. Intended for
    /// `io: .blocking()`.
    public static func blocking(
        address: Kernel.Socket.Address.IPv6,
        io: IO<Sockets.Capabilities>,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let fd = try createBindListen(address: address, backlog: backlog)
        try io.prepare(fd)
        return Sockets.TCP.Listener(fd: consume fd, io: io)
    }

    /// Creates a listener paired with a reactive IO strategy.
    ///
    /// The supplied IO's `prepare` hook establishes its resource invariant.
    /// With `.events()`, this sets `O_NONBLOCK` while preserving other status
    /// flags. `accept(2)` returns `EAGAIN` immediately on an
    /// empty queue, and ``accept()`` awaits `io.ready(from: _fd,
    /// interest: .read)` before retrying. Intended for the reactor- /
    /// events-backed `IO<Sockets.Capabilities>` factory.
    ///
    /// Passing `.blocking()` leaves the descriptor blocking, so the accept
    /// syscall remains the wait point. Prefer
    /// ``blocking(address:io:backlog:)`` to make that pairing explicit.
    public static func reactive(
        address: Kernel.Socket.Address.IPv4,
        io: IO<Sockets.Capabilities>,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let fd = try createBindListen(address: address, backlog: backlog)
        try io.prepare(fd)
        return Sockets.TCP.Listener(fd: consume fd, io: io)
    }

    /// Creates an IPv6 listener paired with a reactive IO strategy.
    ///
    /// The IPv6 companion of the IPv4 `reactive(address:io:backlog:)`
    /// factory; the supplied IO performs preparation and the same accept-loop
    /// pairing applies. Intended for `.events()`.
    public static func reactive(
        address: Kernel.Socket.Address.IPv6,
        io: IO<Sockets.Capabilities>,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let fd = try createBindListen(address: address, backlog: backlog)
        try io.prepare(fd)
        return Sockets.TCP.Listener(fd: consume fd, io: io)
    }

    /// Shared create + bind + listen sequence (IPv4). On throw, the
    /// already-created descriptor's deinit closes the fd automatically.
    /// On success, ownership transfers to the returned value —
    /// `Kernel.Socket.Descriptor` and `Kernel.Descriptor` are the same
    /// move-only type on POSIX (fd = socket).
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

    /// Shared create + bind + listen sequence (IPv6). The IPv6 companion
    /// of the IPv4 `createBindListen` — same discipline, `.inet6` domain
    /// and the IPv6 `bind` overload.
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

// MARK: - Accept

extension Sockets.TCP.Listener {

    /// Accepts a single incoming connection.
    ///
    /// Composes `io.ready(from: _fd, interest: .read)` and
    /// `POSIX.Kernel.Socket.Accept.accept(_fd)` in an `EAGAIN`-retry
    /// loop. Under `.blocking(...)` the `io.ready` call is a no-op on
    /// the blocking strategy and `accept(2)` blocks in the kernel;
    /// `EAGAIN` never fires, so the loop exits on the first iteration.
    /// Under `.reactive(...)` the fd is `O_NONBLOCK`, `io.ready` waits
    /// on kernel readiness, and the subsequent `accept(2)` returns
    /// immediately; `EAGAIN` is observed only for spurious wakeups
    /// (RST-before-accept, load-balancer probe, etc.), in which case
    /// the loop re-arms readiness.
    ///
    /// POSIX wrapper policy: `POSIX.Kernel.Socket.Accept.accept` retries
    /// on EINTR automatically.
    ///
    /// Homes the returned connection's byte-level I/O on this listener's
    /// own `IO` — see the type-level "Head-of-line hazard" note. Use
    /// ``accept(io:)`` to home the connection on a different `IO`.
    public func accept() async throws(Sockets.Error) -> Sockets.TCP.Connection {
        try await accept(io: _io)
    }

    /// Accepts a single incoming connection, homing the returned
    /// connection's byte-level I/O on `io` rather than on this
    /// listener's own `IO`.
    ///
    /// The accept loop itself still waits via this listener's own `_io`
    /// (`_io.ready(from:interest:)`) — only the *returned connection's*
    /// subsequent `read`/`write`/`close` delegate through the supplied
    /// `io`. This is the escape hatch for the head-of-line hazard
    /// documented on ``Sockets/TCP/Listener``: pass an `io` distinct
    /// from the listener's own so a slow or idle connection cannot
    /// starve the listener's accept loop, and so sibling connections
    /// accepted onto their own `io`(s) cannot starve each other.
    ///
    /// ```swift
    /// let listener = try Sockets.TCP.Listener.blocking(
    ///     address: .loopback(port: 0),
    ///     io: listenerIO
    /// )
    /// // Each accepted connection gets its own IO — and thus its own
    /// // dedicated thread under the blocking strategy — rather than
    /// // sharing the listener's.
    /// let connection = try await listener.accept(io: .blocking())
    /// ```
    public func accept(io: IO<Sockets.Capabilities>) async throws(Sockets.Error) -> Sockets.TCP.Connection {
        while true {
            try await _io.ready(from: _fd, interest: .read)

            let result: ISO_9945.Kernel.Socket.Accept.Result
            do throws(Kernel.Socket.Error) {
                result = try POSIX.Kernel.Socket.Accept.accept(_fd)
            } catch {
                // EAGAIN and EWOULDBLOCK share a value on both Darwin (35)
                // and Linux (11); one check covers both. Under .blocking
                // with a blocking-strategy io this path is unreachable
                // (blocking fd + no-op ready + kernel-blocking accept);
                // under .reactive, EAGAIN after a ready signal means
                // spurious wakeup — re-arm readiness and retry.
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

// MARK: - Local Address Discovery

extension Sockets.TCP.Listener {

    /// The port this listener is bound to.
    ///
    /// Queries `getsockname(2)` on the listening descriptor. Useful after
    /// binding with `.loopback(port: 0)` or `.any(port: 0)` to recover the
    /// kernel-assigned ephemeral port for a client to connect to.
    ///
    /// Valid for IPv4 and IPv6 listeners — both carry the port at the same
    /// offset in their `sockaddr` layout (see ``Kernel/Socket/Address/Storage``'s
    /// port reader). Preconditions any other family (a Unix-domain address
    /// has no port).
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
