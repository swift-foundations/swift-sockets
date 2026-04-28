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

// MARK: - Cross-platform Receive surface on POSIX
//
// The `Kernel.Socket.Receive` namespace, `Kernel.Socket.Message.Options`,
// `Kernel.Socket.Message.Header`, and `Kernel.Socket.Address.Storage` are
// declared in swift-iso-9945 (L2 POSIX specification). Windows exposes
// receive syscalls under `Windows.Kernel.Socket.{receive,receiveFrom}`
// with different flag, buffer, and address types via Winsock, so the
// cross-platform `Kernel.Socket.Receive.{receive,from,message}` API is
// POSIX-scoped. A Windows unifier would require promoting typed receive
// surfaces from iso-9945 into kernel-primitives — upstream architecture
// work tracked alongside the sibling gaps flagged by the Accept, Send,
// and Connect cross-platform files.

extension Kernel.Socket.Receive {
    /// Receives bytes from a connected socket into a mutable span,
    /// automatically retrying on `EINTR`.
    ///
    /// Delegates to
    /// ``POSIX/Kernel/Socket/Receive/receive(_:into:options:)`` in
    /// swift-posix (L3 policy — `EINTR` retry). Raw access without retry
    /// is available via
    /// ``ISO_9945/Kernel/Socket/Receive/receive(_:into:options:)``.
    ///
    /// - Parameters:
    ///   - descriptor: The connected socket descriptor.
    ///   - span: The mutable span to receive into.
    ///   - options: Message flags (default: none).
    /// - Returns: Number of bytes received; `0` on orderly shutdown.
    /// - Throws: ``Kernel/Socket/Error`` on failure (excluding `EINTR`).
    @inlinable
    public static func receive(
        _ descriptor: borrowing Kernel.Socket.Descriptor,
        into span: inout MutableSpan<UInt8>,
        options: Kernel.Socket.Message.Options = []
    ) throws(Kernel.Socket.Error) -> Int {
        try POSIX.Kernel.Socket.Receive.receive(descriptor, into: &span, options: options)
    }

    /// Receives bytes and the sender's address into a mutable span,
    /// automatically retrying on `EINTR`.
    ///
    /// Delegates to
    /// ``POSIX/Kernel/Socket/Receive/from(_:into:options:)`` in
    /// swift-posix (L3 policy — `EINTR` retry). Raw access without retry
    /// is available via
    /// ``ISO_9945/Kernel/Socket/Receive/from(_:into:options:)``.
    ///
    /// - Parameters:
    ///   - descriptor: The socket descriptor.
    ///   - span: The mutable span to receive into.
    ///   - options: Message flags (default: none).
    /// - Returns: A tuple of `(count, address, addressLength)`.
    /// - Throws: ``Kernel/Socket/Error`` on failure (excluding `EINTR`).
    @inlinable
    public static func from(
        _ descriptor: borrowing Kernel.Socket.Descriptor,
        into span: inout MutableSpan<UInt8>,
        options: Kernel.Socket.Message.Options = []
    ) throws(Kernel.Socket.Error) -> (count: Int, address: Kernel.Socket.Address.Storage, addressLength: Kernel.Socket.Address.Length) {
        try POSIX.Kernel.Socket.Receive.from(descriptor, into: &span, options: options)
    }

    /// Receives a message with full control over buffers, address, and
    /// ancillary control data, automatically retrying on `EINTR`.
    ///
    /// Delegates to
    /// ``POSIX/Kernel/Socket/Receive/message(_:header:options:)`` in
    /// swift-posix (L3 policy — `EINTR` retry). Raw access without retry
    /// is available via
    /// ``ISO_9945/Kernel/Socket/Receive/message(_:header:options:)``.
    ///
    /// - Parameters:
    ///   - descriptor: The socket descriptor.
    ///   - header: The message header describing receive buffers, address,
    ///     and control data.
    ///   - options: Message flags (default: none).
    /// - Returns: Number of bytes received.
    /// - Throws: ``Kernel/Socket/Error`` on failure (excluding `EINTR`).
    @inlinable
    public static func message(
        _ descriptor: borrowing Kernel.Socket.Descriptor,
        header: inout Kernel.Socket.Message.Header,
        options: Kernel.Socket.Message.Options = []
    ) throws(Kernel.Socket.Error) -> Int {
        try POSIX.Kernel.Socket.Receive.message(descriptor, header: &header, options: options)
    }
}

#endif
