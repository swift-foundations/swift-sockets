//
//  Sockets.TCP.Listener.swift
//  swift-sockets
//

public import IO
import Kernel

extension Sockets.TCP {

    /// TCP listener bound to a local address.
    ///
    /// An actor holding the listening socket and an `IO`. Forwards
    /// `unownedExecutor` to `io.unownedExecutor` so socket syscalls and
    /// accept-result handling run on the `IO`'s dedicated thread (TCA26
    /// shared-executor pattern). Consumers that also forward their own
    /// `unownedExecutor` to this listener elide the per-call hop.
    ///
    /// ## Strategy
    ///
    /// Phase 2A ships the blocking-strategy accept path — `accept(2)` runs
    /// synchronously on the `IO`'s executor thread via actor isolation.
    /// Events- and completions-strategy paths are added in Phase 2B / 2C.
    ///
    /// ## Lifecycle
    ///
    /// The listener owns its listening descriptor for the actor's lifetime.
    /// The default actor deinit drops the stored `Kernel.Socket.Descriptor`,
    /// whose own deinit closes the underlying kernel fd automatically.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let io = IO.blocking()
    /// let listener = try Sockets.TCP.Listener(
    ///     address: .loopback(port: 0),
    ///     io: io
    /// )
    /// let connection = try await listener.accept()
    /// ```
    public actor Listener {

        internal let _fd: Kernel.Socket.Descriptor

        internal let _io: IO

        public nonisolated var unownedExecutor: UnownedSerialExecutor {
            unsafe _io.unownedExecutor
        }

        internal init(fd: consuming Kernel.Socket.Descriptor, io: IO) {
            self._fd = fd
            self._io = io
        }
    }
}

// MARK: - Construction

extension Sockets.TCP.Listener {

    /// Creates a listener bound to the given IPv4 address and listening with
    /// the given backlog.
    ///
    /// Performs `socket(AF_INET, SOCK_STREAM)` + `bind(address)` + `listen()`
    /// in sequence. If `bind` or `listen` throws, the intermediate socket
    /// descriptor is closed automatically by `Kernel.Socket.Descriptor`'s
    /// deinit chain. Failures map to `Sockets.Error.platform`.
    public init(
        address: Kernel.Socket.Address.IPv4,
        io: IO,
        backlog: Kernel.Socket.Backlog = .max
    ) throws(Sockets.Error) {
        let fd: Kernel.Socket.Descriptor
        do throws(Kernel.Socket.Error) {
            fd = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
        } catch {
            throw .platform(error.code)
        }

        // If bind or listen throws, `fd`'s deinit closes the listener fd.
        do throws(Kernel.Socket.Error) {
            try Kernel.Socket.Bind.bind(fd, address: address)
            try Kernel.Socket.Listen.listen(fd, backlog: backlog)
        } catch {
            throw .platform(error.code)
        }

        self.init(fd: fd, io: io)
    }
}

// MARK: - Accept

extension Sockets.TCP.Listener {

    /// Accepts a single incoming connection.
    ///
    /// Blocks the `IO`'s executor thread inside `accept(2)` until a client
    /// connects. Uses `POSIX.Kernel.Socket.Accept.accept` which retries on
    /// EINTR per swift-io's POSIX wrapper policy.
    ///
    /// The accepted socket descriptor is consumed into a `Kernel.Descriptor`
    /// at the boundary (Path A — see `swift-io/Research/io-phase-2-plan.md`
    /// §4.A.0). The returned `Sockets.TCP.Connection` owns the fd and
    /// delegates byte-level I/O through `io`.
    public func accept() throws(Sockets.Error) -> Sockets.TCP.Connection {
        var result: Kernel.Socket.Accept.Result
        do throws(Kernel.Socket.Error) {
            result = try POSIX.Kernel.Socket.Accept.accept(_fd)
        } catch {
            throw .platform(error.code)
        }

        // WORKAROUND: Kernel.Socket.Accept.Result is ~Copyable non-frozen,
        // so partial consumption of `result.descriptor` across the iso-9945
        // module boundary is blocked. Swap-with-sentinel extracts the
        // descriptor without touching the non-frozen layout.
        // WHEN TO REMOVE: once @frozen lands on Kernel.Socket.Accept.Result
        // upstream; switch to `consume result.descriptor`.
        // TRACKING: swift-iso-9945/Research/frozen-accept-result.md
        var extracted = Kernel.Socket.Descriptor.invalid
        Swift.swap(&result.descriptor, &extracted)

        return Sockets.TCP.Connection(
            descriptor: Kernel.Descriptor(consume extracted),
            peer: result.address,
            io: _io
        )
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
