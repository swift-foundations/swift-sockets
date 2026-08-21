public import IO
public import Kernel
public import Span_Raw_Primitives

extension IO where Capabilities == Sockets.Capabilities {

    @inlinable
    public func prepare(
        _ fd: borrowing Kernel.Descriptor
    ) throws(Sockets.Error) {
        try capabilities.prepare(fd)
    }

    @inlinable
    public func read(
        from fd: borrowing Kernel.Descriptor,
        into buffer: Span.Raw.Mutable
    ) async throws(Sockets.Error) -> Int {
        try await capabilities.read(fd, buffer)
    }

    @inlinable
    public func write(
        to fd: borrowing Kernel.Descriptor,
        from buffer: Span.Raw
    ) async throws(Sockets.Error) -> Int {
        try await capabilities.write(fd, buffer)
    }

    @inlinable
    public func close(_ fd: consuming Kernel.Descriptor) async {
        await capabilities.close(consume fd)
    }

    @inlinable
    public func ready(
        from fd: borrowing Kernel.Descriptor,
        interest: Kernel.Event.Interest
    ) async throws(Sockets.Error) {
        try await capabilities.ready(fd, interest)
    }

    @inlinable
    public func connect(
        _ fd: borrowing Kernel.Descriptor,
        to address: Kernel.Socket.Address.Storage,
        length: Kernel.Socket.Address.Length
    ) async throws(Sockets.Error) {
        try await capabilities.connect(fd, address, length)
    }

    @inlinable
    public func send(
        on fd: borrowing Kernel.Descriptor,
        from buffer: Span.Raw,
        to address: Kernel.Socket.Address.Storage,
        length: Kernel.Socket.Address.Length
    ) async throws(Sockets.Error) -> Int {
        try await capabilities.send(fd, buffer, address, length)
    }

    @inlinable
    public func receive(
        on fd: borrowing Kernel.Descriptor,
        into buffer: Span.Raw.Mutable
    ) async throws(Sockets.Error) -> (
        count: Int, peer: Kernel.Socket.Address.Storage, length: Kernel.Socket.Address.Length
    ) {
        try await capabilities.receive(fd, buffer)
    }

    @inlinable
    public var unownedExecutor: UnownedSerialExecutor {
        unsafe runner.executor()
    }
}
