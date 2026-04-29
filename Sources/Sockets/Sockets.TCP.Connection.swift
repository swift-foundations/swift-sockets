//
//  Sockets.TCP.Connection.swift
//  swift-sockets
//

public import IO
import Kernel
import Memory_Primitives

extension Sockets.TCP {

    /// An accepted TCP connection.
    ///
    /// Owns the accepted kernel descriptor and holds the `IO` it was produced
    /// from. Byte-level read/write/close are delegated to the `IO` witness
    /// over the stored ``Kernel/Descriptor`` — the socket-domain typing is
    /// consumed at the accept boundary (Path A — see
    /// `swift-io/Research/io-phase-2-plan.md` §4.A.0).
    ///
    /// ## Ownership
    ///
    /// `Connection` is `~Copyable` — single ownership by construction. When
    /// the value is dropped without an explicit ``close()``, the stored
    /// ``Kernel/Descriptor``'s own deinit closes the underlying fd. ``close()``
    /// is the explicit (typed) cleanup path.
    ///
    /// ## Sendability
    ///
    /// `Sendable` — all stored properties are `Sendable`. Ownership transfer
    /// across isolation boundaries moves the Connection; the `~Copyable`
    /// rule prevents accidental sharing.
    public struct Connection: ~Copyable, Sendable {

        /// The accepted kernel descriptor.
        public let descriptor: Kernel.Descriptor

        /// The peer address the remote side connected from.
        ///
        /// Populated by `accept(2)` — the syscall zero-initializes a
        /// `sockaddr_storage` and fills in the peer's address.
        public let peer: Kernel.Socket.Address.Storage

        /// The `IO` this connection delegates byte-level I/O through.
        public let io: IO

        internal init(
            descriptor: consuming Kernel.Descriptor,
            peer: Kernel.Socket.Address.Storage,
            io: IO
        ) {
            self.descriptor = descriptor
            self.peer = peer
            self.io = io
        }
    }
}

// MARK: - Byte-level I/O

extension Sockets.TCP.Connection {

    /// Read up to `buffer.count` bytes into `buffer`. Returns bytes read (0 at EOF).
    ///
    /// Dispatches to `io.read(from:into:)` with the stored descriptor borrowed
    /// generically. Strategy-specific behavior (blocking syscall vs events
    /// poll-then-read vs completions CQE wait) is supplied by the `IO` value
    /// the connection was constructed with.
    public borrowing func read(
        into buffer: Memory.Buffer.Mutable
    ) async throws(IO.Error) -> Int {
        try await io.read(from: descriptor, into: buffer)
    }

    /// Write up to `buffer.count` bytes from `buffer`. Returns bytes written.
    public borrowing func write(
        from buffer: Memory.Buffer
    ) async throws(IO.Error) -> Int {
        try await io.write(to: descriptor, from: buffer)
    }

    /// Close the connection.
    ///
    /// Consuming — the `Connection` cannot be used after this call. Delegates
    /// to `io.close(_:)` which swallows close errors (the fd is closed at the
    /// kernel level even if the syscall reports an error).
    public consuming func close() async {
        await io.close(consume descriptor)
    }
}

// MARK: - Half-Close

extension Sockets.TCP.Connection {

    /// Shuts down one or both directions of the connection.
    ///
    /// `shutdown(.write)` sends a TCP FIN to the peer — the peer's next
    /// `read` returns 0 (EOF). The local side can still read until the
    /// peer also shuts down its write direction (or closes). This is the
    /// standard half-close pattern for graceful TCP teardown.
    ///
    /// `shutdown(.read)` discards further incoming data. The peer may or
    /// may not see an RST depending on whether it sends after the local
    /// read-side shutdown.
    ///
    /// `shutdown(.both)` is equivalent to `.read` + `.write` in a single
    /// syscall.
    ///
    /// ## Ownership
    ///
    /// `borrowing` — the connection remains valid after a partial shutdown.
    /// A write-shutdown connection can still read; a read-shutdown
    /// connection can still write. Only ``close()`` consumes the
    /// connection.
    public borrowing func shutdown(
        how: Kernel.Socket.Shutdown.How
    ) throws(Sockets.Error) {
        do throws(Kernel.Socket.Shutdown.Error) {
            try Kernel.Socket.Shutdown.shutdown(descriptor, how: how)
        } catch {
            switch error {
            case .platform(let err): throw .platform(err.code)
            case .handle, .io: throw .platform(Error_Primitives.Error.Code.current())
            }
        }
    }
}
