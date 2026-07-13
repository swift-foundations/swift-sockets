//
//  Sockets.Capabilities.swift
//  swift-sockets
//

public import Kernel
public import Span_Raw_Primitives

extension Sockets {
    /// Socket byte-ops capability surface for ``Kernel/Descriptor``.
    ///
    /// Seven `@Sendable` closures describing the operations a strategy
    /// must provide for the sockets domain. Each per-(domain × strategy)
    /// factory constructs a value of this struct and pairs it with an
    /// ``IO/Runner`` via ``IO``'s initializer — see swift-io-primitives'
    /// `IO.swift` for the composition pattern, and `IO+Blocking.swift`
    /// in this package for the Phase 2A blocking factory.
    ///
    /// The sockets domain owns this struct (rather than reusing a
    /// swift-io capability set) because capability sets are domain
    /// vocabulary: operations throw ``Sockets/Error``. Alongside the
    /// stream byte-ops (``read`` / ``write`` / ``close``) and the
    /// readiness primitive (``ready``), the surface carries the
    /// socket-native ``connect`` and the connectionless datagram
    /// ``send`` / ``receive`` — `accept` stays composed at the call site
    /// via ``ready`` (see ``Sockets/TCP/Listener``), matching swift-io's
    /// manifest note on the Test-Support-quarantined Basic domain.
    ///
    /// ## Buffer Ownership
    ///
    /// The ``Span/Raw`` / ``Span/Raw/Mutable`` parameters passed to
    /// `read` / `write` / `send` / `receive` are **non-owning views**.
    /// The caller guarantees the referred memory remains at a stable
    /// address for the duration of the enclosing `try await` expression.
    public struct Capabilities: Sendable {

        /// Read bytes from a descriptor into a mutable buffer. Returns
        /// bytes read, or 0 at EOF.
        public let read:
            @Sendable (
                borrowing Kernel.Descriptor,
                Span.Raw.Mutable
            ) async throws(Sockets.Error) -> Int

        /// Write bytes from a buffer to a descriptor. Returns bytes
        /// written.
        public let write:
            @Sendable (
                borrowing Kernel.Descriptor,
                Span.Raw
            ) async throws(Sockets.Error) -> Int

        /// Close a descriptor. Ownership is consumed.
        public let close: @Sendable (consuming Kernel.Descriptor) async -> Void

        /// Wait for a descriptor to become ready for the requested
        /// interest.
        ///
        /// Readiness composition primitive. Consumers use this to
        /// pre-wait before issuing a socket syscall that is not part of
        /// the capability set (e.g., `POSIX.Kernel.Socket.Accept.accept`
        /// after `ready(listener, .read)`).
        ///
        /// Strategy semantics:
        ///
        /// - **Blocking (Phase 2A)** — no-op. The subsequent syscall is
        ///   the actual block; the executor thread waits there.
        ///   Ready-then-syscall composes correctly with a no-op ready.
        /// - **Events (reactor, Phase 2B)** — register the fd and await
        ///   the kernel readiness event. The fd MUST be in non-blocking
        ///   mode so the subsequent syscall returns immediately.
        /// - **Completions (proactor, Phase 2C)** — submit a poll
        ///   operation and await the completion.
        public let ready:
            @Sendable (
                borrowing Kernel.Descriptor,
                Kernel.Event.Interest
            ) async throws(Sockets.Error) -> Void

        /// Connect a descriptor to a peer address.
        ///
        /// Socket-native operation. The strategy owns the blocking
        /// discipline: the blocking strategy performs an EINTR-safe
        /// blocking `connect(2)`; a reactor-backed strategy switches the
        /// descriptor to non-blocking, initiates the connect, and awaits
        /// write-readiness before checking `SO_ERROR` (see
        /// ``Sockets/TCP/Connection/connect(to:io:)`` for the pairing).
        ///
        /// The address is passed as an opaque
        /// ``Kernel/Socket/Address/Storage`` plus its actual
        /// ``Kernel/Socket/Address/Length`` so the surface stays
        /// address-family-agnostic; the caller converts an `IPv4` / `IPv6`
        /// address to `Storage` at the factory boundary.
        public let connect:
            @Sendable (
                borrowing Kernel.Descriptor,
                Kernel.Socket.Address.Storage,
                Kernel.Socket.Address.Length
            ) async throws(Sockets.Error) -> Void

        /// Send a datagram to a specific address. Returns bytes sent.
        ///
        /// The connectionless send-to primitive (`sendto(2)`) for the UDP
        /// surface. The destination is an opaque
        /// ``Kernel/Socket/Address/Storage`` plus its
        /// ``Kernel/Socket/Address/Length`` — family-agnostic, mirroring
        /// ``connect``.
        public let send:
            @Sendable (
                borrowing Kernel.Descriptor,
                Span.Raw,
                Kernel.Socket.Address.Storage,
                Kernel.Socket.Address.Length
            ) async throws(Sockets.Error) -> Int

        /// Receive a datagram, reporting the sender.
        ///
        /// The connectionless receive-from primitive (`recvfrom(2)`) for
        /// the UDP surface. Returns the byte count alongside the sender's
        /// opaque ``Kernel/Socket/Address/Storage`` and its length.
        public let receive:
            @Sendable (
                borrowing Kernel.Descriptor,
                Span.Raw.Mutable
            ) async throws(Sockets.Error) -> (
                count: Int,
                peer: Kernel.Socket.Address.Storage,
                length: Kernel.Socket.Address.Length
            )

        /// Creates a capability set from its operation closures.
        public init(
            read:
                @Sendable @escaping (
                    borrowing Kernel.Descriptor,
                    Span.Raw.Mutable
                ) async throws(Sockets.Error) -> Int,
            write:
                @Sendable @escaping (
                    borrowing Kernel.Descriptor,
                    Span.Raw
                ) async throws(Sockets.Error) -> Int,
            close: @Sendable @escaping (consuming Kernel.Descriptor) async -> Void,
            ready:
                @Sendable @escaping (
                    borrowing Kernel.Descriptor,
                    Kernel.Event.Interest
                ) async throws(Sockets.Error) -> Void,
            connect:
                @Sendable @escaping (
                    borrowing Kernel.Descriptor,
                    Kernel.Socket.Address.Storage,
                    Kernel.Socket.Address.Length
                ) async throws(Sockets.Error) -> Void,
            send:
                @Sendable @escaping (
                    borrowing Kernel.Descriptor,
                    Span.Raw,
                    Kernel.Socket.Address.Storage,
                    Kernel.Socket.Address.Length
                ) async throws(Sockets.Error) -> Int,
            receive:
                @Sendable @escaping (
                    borrowing Kernel.Descriptor,
                    Span.Raw.Mutable
                ) async throws(Sockets.Error) -> (
                    count: Int,
                    peer: Kernel.Socket.Address.Storage,
                    length: Kernel.Socket.Address.Length
                )
        ) {
            self.read = read
            self.write = write
            self.close = close
            self.ready = ready
            self.connect = connect
            self.send = send
            self.receive = receive
        }
    }
}
