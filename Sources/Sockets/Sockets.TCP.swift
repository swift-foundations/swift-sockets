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
    /// Blocking and event-backed strategies are available. A completions /
    /// proactor strategy remains future work.
    public enum TCP {}
}
