//
//  IO+Sockets.swift
//  swift-sockets
//
//  Labeled forwarding methods on `IO<Sockets.Capabilities>` that
//  delegate to the stored capability closures. Callers write
//  `io.read(from: fd, into: buf)` instead of
//  `io.capabilities.read(fd, buf)`.
//

public import IO
public import Kernel
public import Span_Raw_Primitives

extension IO where Capabilities == Sockets.Capabilities {

    /// Read bytes from `fd` into `buffer`. Returns bytes read, or 0 at
    /// EOF.
    @inlinable
    public func read(
        from fd: borrowing Kernel.Descriptor,
        into buffer: Span.Raw.Mutable
    ) async throws(Sockets.Error) -> Int {
        try await capabilities.read(fd, buffer)
    }

    /// Write bytes from `buffer` to `fd`. Returns bytes written.
    @inlinable
    public func write(
        to fd: borrowing Kernel.Descriptor,
        from buffer: Span.Raw
    ) async throws(Sockets.Error) -> Int {
        try await capabilities.write(fd, buffer)
    }

    /// Close `fd`. Ownership is consumed.
    @inlinable
    public func close(_ fd: consuming Kernel.Descriptor) async {
        await capabilities.close(consume fd)
    }

    /// Wait for `fd` to become ready for the requested interest.
    @inlinable
    public func ready(
        from fd: borrowing Kernel.Descriptor,
        interest: Kernel.Event.Interest
    ) async throws(Sockets.Error) -> Void {
        try await capabilities.ready(fd, interest)
    }

    /// The `UnownedSerialExecutor` this IO is pinned to.
    ///
    /// Forward from a consumer actor's `unownedExecutor` for TCA26
    /// zero-hop co-location:
    ///
    /// ```swift
    /// actor Server {
    ///     let io: IO<Sockets.Capabilities>
    ///     nonisolated var unownedExecutor: UnownedSerialExecutor {
    ///         io.unownedExecutor
    ///     }
    /// }
    /// ```
    @inlinable
    public var unownedExecutor: UnownedSerialExecutor {
        unsafe runner.executor()
    }
}
