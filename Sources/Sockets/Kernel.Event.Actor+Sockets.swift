//
//  Kernel.Event.Actor+Sockets.swift
//  swift-sockets
//

internal import IO
internal import Kernel
internal import Span_Raw_Primitives

extension Kernel.Event.Actor {
    /// Reads once, waiting and re-arming only when the non-blocking
    /// descriptor reports that it would block. A partial count is returned
    /// unchanged; completion policy belongs to the caller.
    internal func read(
        from descriptor: borrowing Kernel.Descriptor,
        into buffer: Span.Raw.Mutable
    ) async throws(Kernel.Event.Failure) -> Int {
        let registration = try register(descriptor)
        while true {
            do throws(Kernel.IO.Read.Error) {
                return try unsafe Kernel.IO.Read.read(
                    descriptor,
                    into: unsafe buffer.base.nonNull
                )
            } catch .blocking(.wouldBlock) {
                try await wait(for: registration, interest: .read)
            } catch {
                throw .right(.platform(error.code))
            }
        }
    }

    /// Writes once, waiting and re-arming only when the non-blocking
    /// descriptor reports that it would block. Partial writes are returned
    /// unchanged so higher layers can advance by the exact count.
    internal func write(
        to descriptor: borrowing Kernel.Descriptor,
        from buffer: Span.Raw
    ) async throws(Kernel.Event.Failure) -> Int {
        let registration = try register(descriptor)
        while true {
            do throws(Kernel.IO.Write.Error) {
                return try unsafe Kernel.IO.Write.write(
                    descriptor,
                    from: unsafe buffer.base.nonNull
                )
            } catch .blocking(.wouldBlock) {
                try await wait(for: registration, interest: .write)
            } catch {
                throw .right(.platform(error.code))
            }
        }
    }

    /// Waits for one readiness interest on a registered descriptor.
    internal func ready(
        from descriptor: borrowing Kernel.Descriptor,
        interest: Kernel.Event.Interest
    ) async throws(Kernel.Event.Failure) {
        let registration = try register(descriptor)
        try await wait(for: registration, interest: interest)
    }

    /// Sends one datagram, preserving the kernel's returned count.
    internal func send(
        on descriptor: borrowing Kernel.Descriptor,
        from buffer: Span.Raw,
        to address: Kernel.Socket.Address.Storage,
        length: Kernel.Socket.Address.Length
    ) async throws(Kernel.Event.Failure) -> Int {
        let registration = try register(descriptor)
        while true {
            do throws(Kernel.Socket.Error) {
                return try POSIX.Kernel.Socket.Send.to(
                    descriptor,
                    from: buffer.span,
                    address: address,
                    addressLength: length
                )
            } catch  where Error_Primitives.Error.Code.POSIX.isEAGAIN(error.code) {
                try await wait(for: registration, interest: .write)
            } catch {
                throw .right(.platform(error.code))
            }
        }
    }

    /// Receives one datagram and returns the kernel-reported sender.
    internal func receive(
        on descriptor: borrowing Kernel.Descriptor,
        into buffer: Span.Raw.Mutable
    ) async throws(Kernel.Event.Failure) -> (
        count: Int,
        peer: Kernel.Socket.Address.Storage,
        length: Kernel.Socket.Address.Length
    ) {
        let registration = try register(descriptor)
        while true {
            var buffer = buffer
            var span = buffer.mutableSpan
            do throws(Kernel.Socket.Error) {
                let result = try POSIX.Kernel.Socket.Receive.from(
                    descriptor,
                    into: &span
                )
                return (
                    count: result.count,
                    peer: result.address,
                    length: result.addressLength
                )
            } catch  where Error_Primitives.Error.Code.POSIX.isEAGAIN(error.code) {
                try await wait(for: registration, interest: .read)
            } catch {
                throw .right(.platform(error.code))
            }
        }
    }

    /// Deregisters before closing so pending waiters observe channel
    /// closure before the descriptor number can be reused.
    internal func close(_ descriptor: consuming Kernel.Descriptor) {
        deregister(Kernel.Event.ID(descriptor: descriptor))
        Sockets.Event.close(consume descriptor)
    }
}
