// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-sockets open source project
//
// Copyright (c) 2024-2026 Coen ten Thije Boonkkamp and the swift-sockets project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS) || os(Linux)

public import Kernel
public import RFC_791
public import RFC_4291

// MARK: - Cross-platform Connect surface on POSIX
//
// Two surface layers:
//
// 1. POSIX-typed overloads (`Storage+length`, `Kernel.Socket.Address.IPv4`,
//    `Kernel.Socket.Address.IPv6`, `Kernel.Socket.Address.Unix`) — thin
//    delegates through `POSIX.Kernel.Socket.Connect.connect`. These take
//    iso-9945's sockaddr-wrapping types directly. POSIX-only; the iso-9945
//    types don't exist on Windows.
//
// 2. Cross-platform RFC-valued overloads (`RFC_791.IPv4.Address` + port,
//    `RFC_4291.IPv6.Address` + port + flow + scope) — portable currency.
//    On POSIX these marshal into iso-9945 sockaddr wrappers at the unifier
//    boundary and delegate to the policy wrapper. When Windows gains a
//    corresponding `Kernel.Socket.Connect+CrossPlatform.Windows.swift`
//    (pending windows-standard sockaddr wrappers), it will expose the same
//    RFC-valued signatures, closing the cross-platform gap without exposing
//    `UnsafePointer<sockaddr>` or platform-specific types.

extension Kernel.Socket.Connect {
    /// Connects a socket to a peer, awaiting completion if interrupted.
    ///
    /// Delegates to ``POSIX/Kernel/Socket/Connect/connect(_:address:length:)``
    /// in swift-posix (L3 policy). On `EINTR`, the policy wrapper does NOT
    /// retry `connect(2)` — the TCP handshake continues asynchronously in the
    /// kernel, so retrying would either race with an in-flight completion or
    /// throw `EALREADY` / `EISCONN`. Instead, the policy wrapper awaits
    /// completion via `poll(POLLOUT)` + `getsockopt(SO_ERROR)` and surfaces
    /// the final connection result.
    ///
    /// Raw access without EINTR completion-await is available via
    /// ``ISO_9945/Kernel/Socket/Connect/connect(_:address:length:)``.
    ///
    /// Non-blocking connect (socket in O_NONBLOCK mode returning `EINPROGRESS`)
    /// is out of scope for this wrapper — consumers managing non-blocking
    /// sockets should use the raw connect and drive completion themselves.
    ///
    /// - Parameters:
    ///   - descriptor: The socket descriptor.
    ///   - address: The peer address, as a `Storage` container.
    ///   - length: The size of the actual address within storage.
    /// - Throws: ``Kernel/Socket/Error`` on failure (excluding EINTR).
    @inlinable
    public static func connect(
        _ descriptor: borrowing Kernel.Socket.Descriptor,
        address: Kernel.Socket.Address.Storage,
        length: Kernel.Socket.Address.Length
    ) throws(Kernel.Socket.Error) {
        try POSIX.Kernel.Socket.Connect.connect(descriptor, address: address, length: length)
    }

    /// Connects a socket to an IPv4 peer, awaiting completion if interrupted.
    ///
    /// See ``connect(_:address:length:)`` for the completion-await semantic.
    ///
    /// - Parameters:
    ///   - descriptor: The socket descriptor.
    ///   - address: The IPv4 peer address.
    /// - Throws: ``Kernel/Socket/Error`` on failure (excluding EINTR).
    @inlinable
    public static func connect(
        _ descriptor: borrowing Kernel.Socket.Descriptor,
        address: Kernel.Socket.Address.IPv4
    ) throws(Kernel.Socket.Error) {
        try POSIX.Kernel.Socket.Connect.connect(descriptor, address: address)
    }

    /// Connects a socket to an IPv6 peer, awaiting completion if interrupted.
    ///
    /// See ``connect(_:address:length:)`` for the completion-await semantic.
    ///
    /// - Parameters:
    ///   - descriptor: The socket descriptor.
    ///   - address: The IPv6 peer address.
    /// - Throws: ``Kernel/Socket/Error`` on failure (excluding EINTR).
    @inlinable
    public static func connect(
        _ descriptor: borrowing Kernel.Socket.Descriptor,
        address: Kernel.Socket.Address.IPv6
    ) throws(Kernel.Socket.Error) {
        try POSIX.Kernel.Socket.Connect.connect(descriptor, address: address)
    }

    /// Connects a socket to a Unix domain peer, awaiting completion if interrupted.
    ///
    /// See ``connect(_:address:length:)`` for the completion-await semantic.
    ///
    /// - Parameters:
    ///   - descriptor: The socket descriptor.
    ///   - address: The Unix domain peer address.
    /// - Throws: ``Kernel/Socket/Error`` on failure (excluding EINTR).
    @inlinable
    public static func connect(
        _ descriptor: borrowing Kernel.Socket.Descriptor,
        address: Kernel.Socket.Address.Unix
    ) throws(Kernel.Socket.Error) {
        try POSIX.Kernel.Socket.Connect.connect(descriptor, address: address)
    }
}

// MARK: - Cross-platform RFC-valued overloads

extension Kernel.Socket.Connect {
    /// Connects a socket to an IPv4 peer identified by an RFC 791 address
    /// and a port, awaiting completion if interrupted.
    ///
    /// Takes the portable currency (``RFC_791/IPv4/Address``) and marshals
    /// it into a POSIX `sockaddr_in` at the unifier boundary: `rawValue` is
    /// host-order, `sin_addr.s_addr` expects network-order, so the marshal
    /// is a single `.bigEndian` swap. See
    /// `swift-institute/Research/ip-address-value-type-memory-layout.md` for
    /// the design rationale.
    ///
    /// See ``connect(_:address:length:)`` for the completion-await semantic.
    ///
    /// - Parameters:
    ///   - descriptor: The socket descriptor.
    ///   - address: The IPv4 peer address.
    ///   - port: Port number in host byte order.
    /// - Throws: ``Kernel/Socket/Error`` on failure (excluding EINTR).
    @inlinable
    public static func connect(
        _ descriptor: borrowing Kernel.Socket.Descriptor,
        address: RFC_791.IPv4.Address,
        port: UInt16
    ) throws(Kernel.Socket.Error) {
        let socketAddress = Kernel.Socket.Address.IPv4(
            address: address.rawValue.bigEndian,
            port: port
        )
        try POSIX.Kernel.Socket.Connect.connect(descriptor, address: socketAddress)
    }

    /// Connects a socket to an IPv6 peer identified by an RFC 4291 address
    /// plus port / flow / scope metadata, awaiting completion if interrupted.
    ///
    /// Marshals the RFC value's 8 host-order segments into 16 network-order
    /// bytes at the unifier boundary, constructs an iso-9945
    /// `Kernel.Socket.Address.IPv6`, and delegates through the POSIX policy
    /// wrapper.
    ///
    /// See ``connect(_:address:length:)`` for the completion-await semantic.
    ///
    /// - Parameters:
    ///   - descriptor: The socket descriptor.
    ///   - address: The IPv6 peer address.
    ///   - port: Port number in host byte order.
    ///   - flowInfo: IPv6 flow information field.
    ///   - scopeId: IPv6 scope identifier.
    /// - Throws: ``Kernel/Socket/Error`` on failure (excluding EINTR).
    @inlinable
    public static func connect(
        _ descriptor: borrowing Kernel.Socket.Descriptor,
        address: RFC_4291.IPv6.Address,
        port: UInt16,
        flowInfo: UInt32 = 0,
        scopeId: UInt32 = 0
    ) throws(Kernel.Socket.Error) {
        let s = address.segments
        let bytes: (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        ) = (
            UInt8(s.0 >> 8), UInt8(s.0 & 0xFF),
            UInt8(s.1 >> 8), UInt8(s.1 & 0xFF),
            UInt8(s.2 >> 8), UInt8(s.2 & 0xFF),
            UInt8(s.3 >> 8), UInt8(s.3 & 0xFF),
            UInt8(s.4 >> 8), UInt8(s.4 & 0xFF),
            UInt8(s.5 >> 8), UInt8(s.5 & 0xFF),
            UInt8(s.6 >> 8), UInt8(s.6 & 0xFF),
            UInt8(s.7 >> 8), UInt8(s.7 & 0xFF)
        )
        let socketAddress = Kernel.Socket.Address.IPv6(
            address: bytes,
            port: port,
            flowInfo: flowInfo,
            scopeId: scopeId
        )
        try POSIX.Kernel.Socket.Connect.connect(descriptor, address: socketAddress)
    }
}

#endif
