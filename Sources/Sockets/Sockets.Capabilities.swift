//
//  Sockets.Capabilities.swift
//  swift-sockets
//

public import Kernel
public import Span_Raw_Primitives

extension Sockets {
    /// Socket byte-ops capability surface for ``Kernel/Descriptor``.
    ///
    /// Four `@Sendable` closures describing the operations a strategy
    /// must provide for the sockets domain. Each per-(domain × strategy)
    /// factory constructs a value of this struct and pairs it with an
    /// ``IO/Runner`` via ``IO``'s initializer — see swift-io-primitives'
    /// `IO.swift` for the composition pattern, and `IO+Blocking.swift`
    /// in this package for the Phase 2A blocking factory.
    ///
    /// The sockets domain owns this struct (rather than reusing a
    /// swift-io capability set) because capability sets are domain
    /// vocabulary: operations throw ``Sockets/Error``, and Phase 2B / 2C
    /// extend the surface with socket-native operations (accept,
    /// connect) that map directly onto proactor submissions — see
    /// swift-io's manifest note on the Test-Support-quarantined Basic
    /// domain.
    ///
    /// ## Buffer Ownership
    ///
    /// The ``Span/Raw`` / ``Span/Raw/Mutable`` parameters passed to
    /// `read` / `write` are **non-owning views**. The caller guarantees
    /// the referred memory remains at a stable address for the duration
    /// of the enclosing `try await` expression.
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

        /// Creates a capability set from its four operation closures.
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
                ) async throws(Sockets.Error) -> Void
        ) {
            self.read = read
            self.write = write
            self.close = close
            self.ready = ready
        }
    }
}
