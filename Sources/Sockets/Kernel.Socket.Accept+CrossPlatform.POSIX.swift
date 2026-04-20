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

// MARK: - Cross-platform Accept surface on POSIX
//
// The `Kernel.Socket.Accept` namespace, its `Result` type, and
// `Kernel.Socket.Address.Storage` are declared in swift-iso-9945 (L2
// POSIX specification), not in swift-kernel-primitives (L1). Windows
// exposes `accept` under `Windows.Kernel.Socket.accept` with a different
// return shape (bare descriptor, raw `sockaddr` pointer) via Winsock, so
// the cross-platform `Kernel.Socket.Accept.accept(_:)` API is POSIX-
// scoped. A Windows unifier would require promoting the typed accept
// result and address storage from iso-9945 into kernel-primitives — that
// is upstream architecture work, tracked alongside the sibling gap
// flagged by `Kernel.Socket.Connect+CrossPlatform.POSIX.swift`.

extension Kernel.Socket.Accept {
    /// Accepts an incoming connection on a listening socket, automatically
    /// retrying on `EINTR`.
    ///
    /// Delegates to ``POSIX/Kernel/Socket/Accept/accept(_:)`` in swift-posix
    /// (L3 policy — `EINTR` retry). Raw access without retry is available
    /// via ``ISO_9945/Kernel/Socket/Accept/accept(_:)``.
    ///
    /// - Parameter descriptor: The listening socket descriptor.
    /// - Returns: A result containing the accepted descriptor and peer
    ///   address.
    /// - Throws: ``Kernel/Socket/Error`` on failure (excluding `EINTR`).
    @inlinable
    public static func accept(
        _ descriptor: borrowing Kernel.Socket.Descriptor
    ) throws(Kernel.Socket.Error) -> Result {
        try POSIX.Kernel.Socket.Accept.accept(descriptor)
    }

    /// Accepts an incoming connection on a generic `Kernel.Descriptor`
    /// holding a listening socket, automatically retrying on `EINTR`.
    ///
    /// Overload for consumers that store listening sockets as the generic
    /// `Kernel.Descriptor` type. The returned `Result` still carries a typed
    /// `Kernel.Socket.Descriptor` for the accepted connection — socket typing
    /// resurfaces at the result boundary where socket semantics matter.
    ///
    /// Delegates to ``POSIX/Kernel/Socket/Accept/accept(_:)-generic-overload``
    /// in swift-posix (L3 policy — `EINTR` retry). Raw access without retry
    /// is available via
    /// ``ISO_9945/Kernel/Socket/Accept/accept(_:)-generic-overload``.
    @inlinable
    public static func accept(
        _ descriptor: borrowing Kernel.Descriptor
    ) throws(Kernel.Socket.Error) -> Result {
        try POSIX.Kernel.Socket.Accept.accept(descriptor)
    }
}

#endif
