//
//  Sockets.Error.swift
//  swift-sockets
//

public import Kernel

extension Sockets {
    /// Error type for socket-specific operations.
    ///
    /// The error domain of ``Sockets/Capabilities`` — every capability
    /// closure throws this type. Holds the socket-flavored cases that do
    /// not belong in a domain-agnostic byte-ops error because they
    /// describe TCP- or socket-specific conditions (`ECONNRESET`,
    /// `ENOTCONN`).
    ///
    /// Cross-layer mappings from the kernel byte-op error types live in
    /// `Sockets.Error+Kernel.swift`; the event strategy mapping lives in
    /// `Sockets.Error+Event.swift`, and a future completions strategy can
    /// add its corresponding mapping. These mappings produce ``cancelled``
    /// and ``ioShutdown``.
    public enum Error: Swift.Error, Equatable {
        /// Descriptor validity failure reported by the typed kernel owner.
        case descriptor(Kernel.Descriptor.Validity.Error)

        /// Reactor registration lifecycle failure expressed without backend
        /// error leakage or invented platform codes.
        case registration(Registration)

        /// Operation attempted on a socket direction already closed.
        case closed(Direction)

        /// Peer reset the connection (ECONNRESET). TCP-specific.
        case connectionReset

        /// Socket is not connected (ENOTCONN). Socket-only. Reserved
        /// for the socket-op layer (shutdown / send on an unconnected
        /// socket); not yet produced by the Phase 2A mappings.
        case notConnected

        /// The task was cancelled during an IO operation. Produced by
        /// the reactor / proactor strategies (Phase 2B / 2C).
        case cancelled

        /// The IO runtime is shutting down. Produced by the reactor /
        /// proactor strategies (Phase 2B / 2C).
        case ioShutdown

        /// The selected IO strategy's deadline elapsed.
        ///
        /// N2 does not add a socket timeout subsystem; this case preserves a
        /// timeout already reported by an injected strategy.
        case timeout

        /// Platform error code (POSIX errno or Win32) not mapped above.
        case platform(Error_Primitives.Error.Code)
    }
}
