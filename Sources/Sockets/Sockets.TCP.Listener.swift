//
//  Sockets.TCP.Listener.swift
//  swift-sockets
//

public import IO
import Kernel

extension Sockets.TCP {

    /// TCP listener bound to a local address.
    ///
    /// An actor holding the listening descriptor and an `IO`. Forwards
    /// `unownedExecutor` to `io.unownedExecutor` so socket syscalls and
    /// accept-result handling run on the `IO`'s dedicated thread (TCA26
    /// shared-executor pattern). Consumers that also forward their own
    /// `unownedExecutor` to this listener elide the per-call hop.
    ///
    /// ## Strategy pairing
    ///
    /// The fd's blocking mode must match the `IO` strategy's `_ready`
    /// semantics (see `swift-io/Sources/IO Core/IO.swift`'s `_ready`
    /// documentation). Two factories make the choice explicit:
    ///
    /// - ``blocking(address:io:backlog:)`` — fd stays in kernel blocking
    ///   mode. `accept(2)` sleeps in the kernel until a connection
    ///   arrives. Intended for `io: IO.blocking()`.
    /// - ``reactive(address:io:backlog:)`` — fd is set to `O_NONBLOCK`.
    ///   `accept(2)` returns `EAGAIN` when the queue is empty; the
    ///   accept loop awaits `io.ready(from: _fd, interest: .read)`
    ///   before retrying. Intended for `io: IO.events()`,
    ///   `IO.completions()` (Linux), or `IO.default()` on a
    ///   reactor-capable host.
    ///
    /// The compiler cannot verify the `io`-to-factory pairing. Mixing
    /// `.reactive(io: IO.blocking())` produces a hot-spin accept loop;
    /// mixing `.blocking(io: IO.events())` risks `accept(2)` blocking
    /// on a spurious wakeup. Match factory to strategy at the call site.
    ///
    /// ## Lifecycle
    ///
    /// The listener owns its listening descriptor for the actor's lifetime.
    /// The default actor deinit drops the stored ``Kernel/Descriptor``,
    /// whose own deinit closes the underlying kernel fd automatically.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let io = IO.blocking()
    /// let listener = try Sockets.TCP.Listener.blocking(
    ///     address: .loopback(port: 0),
    ///     io: io
    /// )
    /// let connection = try await listener.accept()
    /// ```
    public actor Listener {

        internal let _fd: Kernel.Descriptor

        internal let _io: IO

        public nonisolated var unownedExecutor: UnownedSerialExecutor {
            unsafe _io.unownedExecutor
        }

        internal init(fd: consuming Kernel.Descriptor, io: IO) {
            self._fd = fd
            self._io = io
        }
    }
}

// MARK: - Construction

extension Sockets.TCP.Listener {

    /// Creates a listener whose socket remains in blocking mode.
    ///
    /// The listening fd inherits the kernel's default blocking mode —
    /// `accept(2)` sleeps inside the kernel until a connection arrives.
    /// Intended for `io: IO.blocking()`, where `io.ready(...)` is a no-op
    /// and the subsequent `accept(2)` is the actual wait point (see
    /// `swift-io/Sources/IO Core/IO.swift`'s `_ready` contract).
    ///
    /// Passing a reactor-backed `IO` is permitted but semantically off —
    /// `io.ready(...)` will wait on kernel readiness, but the subsequent
    /// `accept(2)` on a blocking fd may re-block on a spurious wakeup
    /// (rare; possible under RST-before-accept and similar edge cases).
    /// Use ``reactive(address:io:backlog:)`` for reactor-backed strategies.
    public static func blocking(
        address: Kernel.Socket.Address.IPv4,
        io: IO,
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
    /// interest: .read)` before retrying. Intended for reactor-backed
    /// `io` — `IO.events()`, `IO.completions()` (Linux), or
    /// `IO.default()` on a reactor host.
    ///
    /// Passing `IO.blocking()` causes a hot-spin: `io.ready(...)` is a
    /// no-op under the blocking strategy, so the retry loop burns CPU
    /// until a connection arrives. Use ``blocking(address:io:backlog:)``
    /// with `IO.blocking()`.
    public static func reactive(
        address: Kernel.Socket.Address.IPv4,
        io: IO,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) -> Sockets.TCP.Listener {
        let fd = try createBindListen(address: address, backlog: backlog)

        do throws(Kernel.File.Control.Error) {
            try Kernel.File.Control.setNonBlocking(fd)
        } catch {
            switch error {
            case .platform(let err): throw .platform(err.code)
            case .handle, .io: throw .platform(Kernel.Error.Code.current())
            }
        }

        return Sockets.TCP.Listener(fd: consume fd, io: io)
    }

    /// Shared create + bind + listen sequence. On throw, the intermediate
    /// `Kernel.Socket.Descriptor` deinit closes the fd automatically.
    /// Ownership transfers to the returned `Kernel.Descriptor` on success.
    private static func createBindListen(
        address: Kernel.Socket.Address.IPv4,
        backlog: Kernel.Socket.Backlog
    ) throws(Sockets.Error) -> Kernel.Descriptor {
        let socket: Kernel.Socket.Descriptor
        do throws(Kernel.Socket.Error) {
            socket = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
        } catch {
            throw .platform(error.code)
        }

        do throws(Kernel.Socket.Error) {
            try Kernel.Socket.Bind.bind(socket, address: address)
            try Kernel.Socket.Listen.listen(socket, backlog: backlog)
        } catch {
            throw .platform(error.code)
        }

        return Kernel.Descriptor(consume socket)
    }
}

// MARK: - Accept

extension Sockets.TCP.Listener {

    /// Accepts a single incoming connection.
    ///
    /// Composes `io.ready(from: _fd, interest: .read)` and
    /// `POSIX.Kernel.Socket.Accept.accept(_fd)` in an `EAGAIN`-retry
    /// loop. Under `.blocking(...)` the `io.ready` call is a no-op on
    /// `IO.blocking()` and `accept(2)` blocks in the kernel; `EAGAIN`
    /// never fires, so the loop exits on the first iteration. Under
    /// `.reactive(...)` the fd is `O_NONBLOCK`, `io.ready` waits on
    /// kernel readiness, and the subsequent `accept(2)` returns
    /// immediately; `EAGAIN` is observed only for spurious wakeups
    /// (RST-before-accept, load-balancer probe, etc.), in which case
    /// the loop re-arms readiness.
    ///
    /// POSIX wrapper policy: `POSIX.Kernel.Socket.Accept.accept` retries
    /// on EINTR automatically.
    public func accept() async throws(Sockets.Error) -> Sockets.TCP.Connection {
        while true {
            do throws(IO.Error) {
                try await _io.ready(from: _fd, interest: .read)
            } catch {
                throw .platform(Kernel.Error.Code.current())
            }

            let result: Kernel.Socket.Accept.Result
            do throws(Kernel.Socket.Error) {
                result = try POSIX.Kernel.Socket.Accept.accept(_fd)
            } catch {
                // EAGAIN and EWOULDBLOCK share a value on both Darwin (35)
                // and Linux (11); one check covers both. Under .blocking
                // with IO.blocking() this path is unreachable (blocking
                // fd + no-op ready + kernel-blocking accept); under
                // .reactive, EAGAIN after a ready signal means spurious
                // wakeup — re-arm readiness and retry.
                if error.code == .POSIX.EAGAIN {
                    continue
                }
                throw .platform(error.code)
            }

            return Sockets.TCP.Connection(
                descriptor: Kernel.Descriptor(consume result.descriptor),
                peer: result.address,
                io: _io
            )
        }
    }
}

// MARK: - Local Address Discovery

extension Sockets.TCP.Listener {

    /// The IPv4 port this listener is bound to.
    ///
    /// Queries `getsockname(2)` on the listening descriptor. Useful after
    /// binding with `.loopback(port: 0)` or `.any(port: 0)` to recover the
    /// kernel-assigned ephemeral port for a client to connect to.
    ///
    /// Preconditions that the listener is bound to an IPv4 address; 2A
    /// ships IPv4 TCP only. Subsequent sub-phases will add IPv6 and Unix
    /// variants with their own address accessors.
    public func port() throws(Sockets.Error) -> UInt16 {
        let storage: Kernel.Socket.Address.Storage
        do throws(Kernel.Socket.Error) {
            storage = try Kernel.Socket.Name.local(_fd).address
        } catch {
            throw .platform(error.code)
        }
        precondition(
            storage.family == .inet,
            "Sockets.TCP.Listener.port() is only valid for IPv4 listeners; got \(storage.family)."
        )
        // sockaddr_in layout: sa_family_t (2 bytes) | sin_port (2 bytes, big-endian).
        return unsafe storage.withUnsafeBytes { raw, _ in
            let networkPort = unsafe raw.load(fromByteOffset: 2, as: UInt16.self)
            return UInt16(bigEndian: networkPort)
        }
    }
}
