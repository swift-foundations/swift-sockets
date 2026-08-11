//
//  Socket.swift
//  swift-sockets
//

/// Canonical channel-facing socket vocabulary.
///
/// `Socket` is the consumer-facing layer over the retained `Sockets.TCP` and
/// `Sockets.UDP` descriptor owners. It does not introduce another I/O runtime:
/// duplex byte flow is owned by ``IO/Byte/Channel`` and descriptor operations
/// remain owned by the existing concrete socket types. `Sockets.TCP` and
/// `Sockets.UDP` remain source-compatible compatibility surfaces, including
/// for TLS's current `Sockets.TCP.Connection` composition.
public enum Socket {}

extension Socket {
    /// The failure domain carried by socket byte channels.
    public typealias Error = Sockets.Error
}
