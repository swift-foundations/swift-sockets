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

// MARK: - Cross-platform Send surface on POSIX
//
// The `Kernel.Socket.Send` namespace, `Kernel.Socket.Message.Options`,
// `Kernel.Socket.Message.Header`, and `Kernel.Socket.Address.Storage` are
// declared in swift-iso-9945 (L2 POSIX specification). Windows exposes
// send syscalls under `Windows.Kernel.Socket.{send,sendTo}` with different
// flag, buffer, and address types via Winsock, so the cross-platform
// `Kernel.Socket.Send.{send,to,message}` API is POSIX-scoped. A Windows
// unifier would require promoting typed send surfaces from iso-9945 into
// kernel-primitives — upstream architecture work tracked alongside the
// sibling gaps flagged by the Accept and Connect cross-platform files.

extension Kernel.Socket.Send {
    /// Sends bytes from a span on a connected socket, automatically
    /// retrying on `EINTR`.
    ///
    /// Delegates to ``POSIX/Kernel/Socket/Send/send(_:from:options:)`` in
    /// swift-posix (L3 policy — `EINTR` retry). Raw access without retry
    /// is available via
    /// ``ISO_9945/Kernel/Socket/Send/send(_:from:options:)``.
    ///
    /// - Parameters:
    ///   - descriptor: The connected socket descriptor.
    ///   - span: The data to send.
    ///   - options: Message flags (default: none).
    /// - Returns: Number of bytes sent.
    /// - Throws: ``Kernel/Socket/Error`` on failure (excluding `EINTR`).
    @inlinable
    public static func send(
        _ descriptor: borrowing Kernel.Socket.Descriptor,
        from span: Span<UInt8>,
        options: Kernel.Socket.Message.Options = []
    ) throws(Kernel.Socket.Error) -> Int {
        try POSIX.Kernel.Socket.Send.send(descriptor, from: span, options: options)
    }

    /// Sends bytes from a span to an explicit destination address
    /// (connectionless sockets), automatically retrying on `EINTR`.
    ///
    /// Delegates to
    /// ``POSIX/Kernel/Socket/Send/to(_:from:options:address:addressLength:)``
    /// in swift-posix (L3 policy — `EINTR` retry). Raw access without
    /// retry is available via
    /// ``ISO_9945/Kernel/Socket/Send/to(_:from:options:address:addressLength:)``.
    ///
    /// - Parameters:
    ///   - descriptor: The socket descriptor.
    ///   - span: The data to send.
    ///   - options: Message flags (default: none).
    ///   - address: The destination address.
    ///   - addressLength: The size of the actual address within storage.
    /// - Returns: Number of bytes sent.
    /// - Throws: ``Kernel/Socket/Error`` on failure (excluding `EINTR`).
    @inlinable
    public static func to(
        _ descriptor: borrowing Kernel.Socket.Descriptor,
        from span: Span<UInt8>,
        options: Kernel.Socket.Message.Options = [],
        address: Kernel.Socket.Address.Storage,
        addressLength: Kernel.Socket.Address.Length
    ) throws(Kernel.Socket.Error) -> Int {
        try POSIX.Kernel.Socket.Send.to(
            descriptor,
            from: span,
            options: options,
            address: address,
            addressLength: addressLength
        )
    }

    /// Sends a message with full control over buffers, address, and
    /// ancillary control data, automatically retrying on `EINTR`.
    ///
    /// Delegates to
    /// ``POSIX/Kernel/Socket/Send/message(_:header:options:)`` in
    /// swift-posix (L3 policy — `EINTR` retry). Raw access without retry
    /// is available via
    /// ``ISO_9945/Kernel/Socket/Send/message(_:header:options:)``.
    ///
    /// - Parameters:
    ///   - descriptor: The socket descriptor.
    ///   - header: The message header describing buffers, address, and
    ///     control data.
    ///   - options: Message flags (default: none).
    /// - Returns: Number of bytes sent.
    /// - Throws: ``Kernel/Socket/Error`` on failure (excluding `EINTR`).
    @inlinable
    public static func message(
        _ descriptor: borrowing Kernel.Socket.Descriptor,
        header: inout Kernel.Socket.Message.Header,
        options: Kernel.Socket.Message.Options = []
    ) throws(Kernel.Socket.Error) -> Int {
        try POSIX.Kernel.Socket.Send.message(descriptor, header: &header, options: options)
    }
}

#endif
