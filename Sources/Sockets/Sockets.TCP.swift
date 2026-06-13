//
//  Sockets.TCP.swift
//  swift-sockets
//

extension Sockets {
    /// TCP socket domain.
    ///
    /// Provides the passive and connected endpoints for TCP streams:
    /// ``Sockets/TCP/Listener`` accepts incoming connections; ``Sockets/TCP/Connection``
    /// represents a connected pair. Both compose with the blocking strategy
    /// via the shared-executor pattern — socket syscalls run on the
    /// `IO<Sockets.Capabilities>`'s executor thread, and byte-level I/O
    /// flows through the capability closures.
    ///
    /// Phase 2A ships the blocking-strategy implementation. Events- and
    /// completions-strategy code paths are added in Phase 2B / 2C.
    public enum TCP {}
}
