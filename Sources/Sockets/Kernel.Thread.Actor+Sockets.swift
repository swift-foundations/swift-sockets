//
//  Kernel.Thread.Actor+Sockets.swift
//  swift-sockets
//
//  Sockets-domain syscall bindings attached to Kernel.Thread.Actor
//  (swift-threads). Actor isolation guarantees each method runs on the
//  actor's pinned OS thread; the blocking factory's capability closures
//  forward here. Internal — consumers reach these operations through
//  the `IO<Sockets.Capabilities>` surface.
//

internal import Kernel
internal import Span_Raw_Primitives
internal import Thread_Actor

extension Kernel.Thread.Actor {

    /// Read bytes from `descriptor` into `buffer` on the actor's pinned
    /// OS thread. Returns bytes read, or 0 at EOF.
    internal func read(
        from descriptor: borrowing Kernel.Descriptor,
        into buffer: Span.Raw.Mutable
    ) throws(Sockets.Error) -> Int {
        do throws(Kernel.IO.Read.Error) {
            return try unsafe Kernel.IO.Read.read(descriptor, into: unsafe buffer.base.nonNull)
        } catch {
            throw Sockets.Error(error)
        }
    }

    /// Write bytes from `buffer` to `descriptor` on the actor's pinned
    /// OS thread. Returns bytes written.
    internal func write(
        to descriptor: borrowing Kernel.Descriptor,
        from buffer: Span.Raw
    ) throws(Sockets.Error) -> Int {
        do throws(Kernel.IO.Write.Error) {
            return try unsafe Kernel.IO.Write.write(descriptor, from: unsafe buffer.base.nonNull)
        } catch {
            throw Sockets.Error(error)
        }
    }

    /// Close `descriptor` on the actor's pinned OS thread.
    ///
    /// Close errors are swallowed — the fd is closed at the kernel
    /// level even when the syscall reports an error, and close errors
    /// (e.g., EINTR on NFS) are rarely actionable.
    internal func close(_ descriptor: consuming Kernel.Descriptor) {
        do throws(Kernel.Close.Error) {
            try Kernel.Close.close(consume descriptor)
        } catch {
            // fd is already closed — error is informational only.
        }
    }
}
