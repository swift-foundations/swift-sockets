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
    /// The fd's blocking mode must match the `IO` strategy's `ready`
    /// semantics (see ``Sockets/Capabilities/ready``). Two factories
    /// make the choice explicit:
    ///
    /// - ``blocking(address:io:backlog:)`` — fd stays in kernel blocking
    ///   mode. `accept(2)` sleeps in the kernel until a connection
    ///   arrives. Intended for `io: .blocking()`.
    /// - ``reactive(address:io:backlog:)`` — fd is set to `O_NONBLOCK`.
    ///   `accept(2)` returns `EAGAIN` when the queue is empty; the
    ///   accept loop awaits `io.ready(from: _fd, interest: .read)`
    ///   before retrying. Intended for the reactor- / proactor-backed
    ///   factories arriving in Phase 2B / 2C.
    ///
    /// The compiler cannot verify the `io`-to-factory pairing. Mixing
    /// `.reactive` with a blocking-strategy `io` produces a hot-spin
    /// accept loop; mixing `.blocking` with a reactor-backed `io` risks
    /// `accept(2)` blocking on a spurious wakeup. Match factory to
    /// strategy at the call site.
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

    /// Creates a listener whose socket remains in blocking mode.
    ///
    /// The listening fd inherits the kernel's default blocking mode —
    /// `accept(2)` sleeps inside the kernel until a connection arrives.
    /// Intended for `io: .blocking()`, where `io.ready(...)` is a no-op
    /// and the subsequent `accept(2)` is the actual wait point (see
    /// ``Sockets/Capabilities/ready``).
    ///
    /// Passing a reactor-backed `IO` is permitted but semantically off —
    /// `io.ready(...)` will wait on kernel readiness, but the subsequent
    /// `accept(2)` on a blocking fd may re-block on a spurious wakeup
    /// (rare; possible under RST-before-accept and similar edge cases).
    /// Use ``reactive(address:io:backlog:)`` for reactor-backed strategies.
    public static func blocking(
        address: Kernel.Socket.Address.IPv4,
        io: IO<Sockets.Capabilities>,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let fd = try createBindListen(address: address, backlog: backlog)
        return Sockets.TCP.Listener(fd: consume fd, io: io)
    }

    /// Creates an IPv6 listener whose socket remains in blocking mode.
    ///
    /// The IPv6 companion of the IPv4 `blocking(address:io:backlog:)`
    /// factory; the fd inherits the kernel's default blocking mode and the
    /// same strategy pairing applies. Intended for `io: .blocking()`.
    public static func blocking(
        address: Kernel.Socket.Address.IPv6,
        io: IO<Sockets.Capabilities>,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let fd = try createBindListen(address: address, backlog: backlog)
        return Sockets.TCP.Listener(fd: consume fd, io: io)
    }

    /// Creates a listener whose socket is set to non-blocking mode.
    ///
    /// The listening fd is switched to `O_NONBLOCK` at init time via
    /// `fcntl(F_SETFL)`. `accept(2)` returns `EAGAIN` immediately on an
    /// empty queue, and ``accept()`` awaits `io.ready(from: _fd,
    /// interest: .read)` before retrying. Intended for the reactor- /
    /// proactor-backed `IO<Sockets.Capabilities>` factories arriving in
    /// Phase 2B / 2C.
    ///
    /// Passing a blocking-strategy `io` causes a hot-spin: `io.ready(...)`
    /// is a no-op under the blocking strategy, so the retry loop burns
    /// CPU until a connection arrives. Use ``blocking(address:io:backlog:)``
    /// with `.blocking()`.
    public static func reactive(
        address: Kernel.Socket.Address.IPv4,
        io: IO<Sockets.Capabilities>,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let fd = try createBindListen(address: address, backlog: backlog)
        try makeNonBlocking(fd)
        return Sockets.TCP.Listener(fd: consume fd, io: io)
    }

    /// Creates an IPv6 listener whose socket is set to non-blocking mode.
    ///
    /// The IPv6 companion of the IPv4 `reactive(address:io:backlog:)`
    /// factory; the fd is switched to `O_NONBLOCK` and the same accept-loop
    /// / strategy pairing applies. Intended for the reactor- / proactor-backed
    /// `IO<Sockets.Capabilities>` factories.
    public static func reactive(
        address: Kernel.Socket.Address.IPv6,
        io: IO<Sockets.Capabilities>,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let fd = try createBindListen(address: address, backlog: backlog)
        try makeNonBlocking(fd)
        return Sockets.TCP.Listener(fd: consume fd, io: io)
    }

    /// Shared `O_NONBLOCK` switch used by the `.reactive` factories.
    private static func makeNonBlocking(
        _ fd: borrowing Kernel.Descriptor
    ) throws(Sockets.Error) {
        do throws(Kernel.File.Control.Error) {
            try Kernel.File.Control.setNonBlocking(fd)
        } catch {
            switch error {
            case .platform(let err): throw .platform(err.code)
            case .handle(let err): throw .platform(err.code)
            }
        }
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
    public func accept() async throws(Sockets.Error) -> Sockets.TCP.Connection {
        while true {
            try await _io.ready(from: _fd, interest: .read)

            do throws(Kernel.Socket.Error) {
                // `result`'s type is inferred from the accept return
                // (`ISO_9945.Kernel.Socket.Accept.Result`): naming it
                // explicitly is not possible here because the
                // cross-platform `Kernel.Socket.Accept` resolves to the
                // POSIX EINTR-policy enum, which owns the `accept` method
                // but not the `Result` type (that lives in the L2 spec).
                let result = try POSIX.Kernel.Socket.Accept.accept(_fd)
                let peer = result.address
                return Sockets.TCP.Connection(
                    descriptor: consume result.descriptor,
                    peer: peer,
                    io: _io
                )
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
