//
//  Sockets.Error.swift
//  swift-sockets
//

public import Kernel
internal import IO_Core

extension Sockets {
    /// Error type for socket-specific operations.
    ///
    /// Holds the socket-flavored cases that do not belong in the domain-
    /// agnostic `IO.Error` because they describe TCP- or socket-specific
    /// conditions (`ECONNRESET`, `ENOTCONN`). Migrated from swift-io's
    /// `IO.Error` under the domain-agnostic architecture (see
    /// swift-io/Research/io-architecture.md v1.1).
    ///
    /// Phase 1 establishes the destination type; it is not yet consumed —
    /// socket code still lives under swift-io/Sources/IO Events/ and
    /// swift-io/Sources/IO Completions/ pending Phase 2 migration.
    public enum Error: Swift.Error, Equatable {
        /// Peer reset the connection (ECONNRESET). TCP-specific.
        case connectionReset

        /// Socket is not connected (ENOTCONN). Socket-only.
        case notConnected

        /// The task was cancelled during an IO operation.
        case cancelled

        /// The IO runtime is shutting down.
        case ioShutdown

        /// Platform error code (POSIX errno or Win32) not mapped above.
        case platform(Kernel.Error.Code)

        /// Maps an `IO.Error` to a `Sockets.Error`, preserving cancellation
        /// and shutdown semantics rather than erasing them to `.platform`.
        internal init(_ ioError: IO.Error) {
            switch ioError {
            case .cancelled: self = .cancelled
            case .shutdown: self = .ioShutdown
            case .brokenPipe: self = .platform(.POSIX.EPIPE)
            case .timeout: self = .platform(Kernel.Error.Code.current())
            case .platform(let code): self = .platform(code)
            }
        }
    }
}
