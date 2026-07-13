//
//  Kernel.Socket.Address.Storage+Port.swift
//  swift-sockets
//
//  Shared port reader for a bound socket's local/peer address. Backs the
//  `port()` accessors on `Sockets.TCP.Listener` and `Sockets.UDP.Endpoint`
//  after a `getsockname(2)` on a `.loopback(port: 0)` / `.any(port: 0)`
//  bind recovers the kernel-assigned ephemeral port.
//

internal import Kernel

extension Kernel.Socket.Address.Storage {

    /// The port number carried by an IPv4 or IPv6 socket address.
    ///
    /// `sockaddr_in` and `sockaddr_in6` both store the 16-bit port in
    /// network byte order at byte offset 2 (`sin_port` / `sin6_port`
    /// follow the 2-byte family field in each layout), so one reader
    /// covers both families. Preconditions the storage is IPv4 or IPv6 —
    /// no other family carries a port at this offset.
    internal var _port: UInt16 {
        precondition(
            family == .inet || family == .inet6,
            "Storage._port is only valid for IPv4/IPv6 addresses; got \(family)."
        )
        // sockaddr_in / sockaddr_in6 layout: sa_family_t (2 bytes) |
        // port (2 bytes, big-endian).
        return unsafe withUnsafeBytes { raw, _ in
            let networkPort = unsafe raw.load(fromByteOffset: 2, as: UInt16.self)
            return UInt16(bigEndian: networkPort)
        }
    }
}
