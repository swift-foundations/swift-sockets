//
//  Sockets.TCP.Listener.Capabilities.swift
//  swift-sockets
//

public import IO

extension Sockets.TCP.Listener {
    /// Strategy state for cancellable listener acceptance and release.
    ///
    /// This is deliberately distinct from ``Sockets/Capabilities``. Stream
    /// and datagram byte operations have a lawful blocking implementation;
    /// listener release requires externally cancellable admission plus a
    /// linear acknowledgement of physical completion. Only strategies that
    /// provide that lifecycle may construct this capability.
    public struct Capabilities: Sendable {
        internal let strategy: any Sockets.TCP.Listener.Strategy

        internal init(strategy: any Sockets.TCP.Listener.Strategy) {
            self.strategy = strategy
        }
    }
}
