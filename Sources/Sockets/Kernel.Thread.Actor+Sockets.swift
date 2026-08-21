internal import Kernel
internal import Span_Raw_Primitives
internal import Thread_Actor

extension Kernel.Thread.Actor {

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

    internal func close(_ descriptor: consuming Kernel.Descriptor) {
        do throws(Kernel.Close.Error) {
            try Kernel.Close.close(consume descriptor)
        } catch {

        }
    }

    internal func connect(
        _ descriptor: borrowing Kernel.Descriptor,
        to address: Kernel.Socket.Address.Storage,
        length: Kernel.Socket.Address.Length
    ) throws(Sockets.Error) {
        do throws(Kernel.Socket.Error) {
            try POSIX.Kernel.Socket.Connect.connect(descriptor, address: address, length: length)
        } catch {
            throw Sockets.Error(error)
        }
    }

    internal func send(
        on descriptor: borrowing Kernel.Descriptor,
        from buffer: Span.Raw,
        to address: Kernel.Socket.Address.Storage,
        length: Kernel.Socket.Address.Length
    ) throws(Sockets.Error) -> Int {
        do throws(Kernel.Socket.Error) {
            return try POSIX.Kernel.Socket.Send.to(
                descriptor,
                from: buffer.span,
                address: address,
                addressLength: length
            )
        } catch {
            throw Sockets.Error(error)
        }
    }

    internal func receive(
        on descriptor: borrowing Kernel.Descriptor,
        into buffer: Span.Raw.Mutable
    ) throws(Sockets.Error) -> (
        count: Int, peer: Kernel.Socket.Address.Storage, length: Kernel.Socket.Address.Length
    ) {
        var buffer = buffer
        var span = buffer.mutableSpan
        do throws(Kernel.Socket.Error) {
            let result = try POSIX.Kernel.Socket.Receive.from(descriptor, into: &span)
            return (count: result.count, peer: result.address, length: result.addressLength)
        } catch {
            throw Sockets.Error(error)
        }
    }
}
