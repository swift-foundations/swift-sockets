//
//  Sockets.UDP.Endpoint.swift
//  swift-sockets
//

public import IO
public import Kernel
public import Span_Raw_Primitives

extension Sockets.UDP {

    /// A bound UDP datagram endpoint.
    ///
    /// Owns a `.datagram` kernel descriptor bound to a local address and
    /// holds the `IO<Sockets.Capabilities>` it delegates datagram I/O
    /// through. `sendto(2)` / `recvfrom(2)` flow through the capability
    /// closures over the stored ``Kernel/Descriptor`` — the same
    /// shared-executor composition ``Sockets/TCP/Connection`` uses for
    /// stream bytes.
    ///
    /// ## Ownership
    ///
    /// `Endpoint` is `~Copyable` — single ownership by construction. When
    /// the value is dropped without an explicit ``close()``, the stored
    /// ``Kernel/Descriptor``'s own deinit closes the underlying fd.
    /// ``close()`` is the explicit cleanup path.
    ///
    /// ## Sendability
    ///
    /// `Sendable` — all stored properties are `Sendable`. Ownership transfer
    /// across isolation boundaries moves the Endpoint; the `~Copyable` rule
    /// prevents accidental sharing.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let io: IO<Sockets.Capabilities> = .blocking()
    /// let endpoint = try Sockets.UDP.Endpoint.bound(
    ///     to: .loopback(port: 0),
    ///     io: io
    /// )
    /// let port = try endpoint.port()
    /// ```
    public struct Endpoint: ~Copyable, Sendable {

        /// The bound datagram descriptor.
        public let descriptor: Kernel.Descriptor

        /// The `IO` this endpoint delegates datagram I/O through.
        public let io: IO<Sockets.Capabilities>

        internal init(
            descriptor: consuming Kernel.Descriptor,
            io: IO<Sockets.Capabilities>
        ) {
            self.descriptor = descriptor
            self.io = io
        }
    }
}

// MARK: - Construction

extension Sockets.UDP.Endpoint {

    /// Creates a UDP endpoint bound to an IPv4 address.
    ///
    /// Creates a `.datagram` socket in the `.inet` domain and binds it to
    /// `address`. Bind with `.loopback(port: 0)` or `.any(port: 0)` and
    /// recover the kernel-assigned port via ``port()``.
    ///
    /// Before exposure, the factory invokes `io.prepare` once. With
    /// `.blocking()` the descriptor stays in the kernel's default blocking
    /// mode; with `.events()` it becomes non-blocking and readiness gates
    /// datagram I/O.
    public static func bound(
        to address: Kernel.Socket.Address.IPv4,
        io: IO<Sockets.Capabilities>
    ) throws(Sockets.Error) -> Sockets.UDP.Endpoint {
        let fd = try createBind(address: address)
        try io.prepare(fd)
        return Sockets.UDP.Endpoint(descriptor: consume fd, io: io)
    }

    /// Creates a UDP endpoint bound to an IPv6 address.
    ///
    /// The IPv6 companion of the IPv4 `bound(to:io:)` factory — creates a
    /// `.datagram` socket in the `.inet6` domain.
    public static func bound(
        to address: Kernel.Socket.Address.IPv6,
        io: IO<Sockets.Capabilities>
    ) throws(Sockets.Error) -> Sockets.UDP.Endpoint {
        let fd = try createBind(address: address)
        try io.prepare(fd)
        return Sockets.UDP.Endpoint(descriptor: consume fd, io: io)
    }

    /// Shared create + bind sequence (IPv4). On throw, the already-created
    /// descriptor's deinit closes the fd automatically; on success,
    /// ownership transfers to the returned value.
    private static func createBind(
        address: Kernel.Socket.Address.IPv4
    ) throws(Sockets.Error) -> Kernel.Descriptor {
        do throws(Kernel.Socket.Error) {
            let socket = try Kernel.Socket.Create.create(domain: .inet, kind: .datagram)
            try Kernel.Socket.Bind.bind(socket, address: address)
            return socket
        } catch {
            throw .platform(error.code)
        }
    }

    /// Shared create + bind sequence (IPv6).
    private static func createBind(
        address: Kernel.Socket.Address.IPv6
    ) throws(Sockets.Error) -> Kernel.Descriptor {
        do throws(Kernel.Socket.Error) {
            let socket = try Kernel.Socket.Create.create(domain: .inet6, kind: .datagram)
            try Kernel.Socket.Bind.bind(socket, address: address)
            return socket
        } catch {
            throw .platform(error.code)
        }
    }
}

// MARK: - Datagram I/O

extension Sockets.UDP.Endpoint {

    /// Sends `buffer` as a single datagram to `peer`. Returns bytes sent.
    ///
    /// The address-family-agnostic primitive: `peer` is an opaque
    /// ``Kernel/Socket/Address/Storage`` plus its `length`, as reported by
    /// ``receive(into:)``. Use it to reply to a datagram's sender; the
    /// typed `IPv4` / `IPv6` overloads forward here.
    public borrowing func send(
        _ buffer: Span.Raw,
        to peer: Kernel.Socket.Address.Storage,
        length: Kernel.Socket.Address.Length
    ) async throws(Sockets.Error) -> Int {
        try await io.send(on: descriptor, from: buffer, to: peer, length: length)
    }

    /// Sends `buffer` as a single datagram to an IPv4 address. Returns
    /// bytes sent.
    public borrowing func send(
        _ buffer: Span.Raw,
        to address: Kernel.Socket.Address.IPv4
    ) async throws(Sockets.Error) -> Int {
        try await send(buffer, to: address.storage, length: Kernel.Socket.Address.IPv4.size)
    }

    /// Sends `buffer` as a single datagram to an IPv6 address. Returns
    /// bytes sent.
    public borrowing func send(
        _ buffer: Span.Raw,
        to address: Kernel.Socket.Address.IPv6
    ) async throws(Sockets.Error) -> Int {
        try await send(buffer, to: address.storage, length: Kernel.Socket.Address.IPv6.size)
    }

    /// Receives a single datagram into `buffer`.
    ///
    /// Returns the byte count alongside the sender's address and its
    /// length. The peer can be passed straight back to ``send(_:to:length:)``
    /// to reply. Dispatches to `io.receive(on:into:)` with the stored
    /// descriptor borrowed.
    public borrowing func receive(
        into buffer: Span.Raw.Mutable
    ) async throws(Sockets.Error) -> (count: Int, peer: Kernel.Socket.Address.Storage, length: Kernel.Socket.Address.Length) {
        try await io.receive(on: descriptor, into: buffer)
    }

    /// Close the endpoint.
    ///
    /// Consuming — the `Endpoint` cannot be used after this call. Delegates
    /// to `io.close(_:)` which swallows close errors (the fd is closed at
    /// the kernel level even if the syscall reports an error).
    public consuming func close() async {
        await io.close(consume descriptor)
    }
}

// MARK: - Local Address Discovery

extension Sockets.UDP.Endpoint {

    /// The port this endpoint is bound to.
    ///
    /// Queries `getsockname(2)` on the datagram descriptor. Useful after
    /// binding with `.loopback(port: 0)` or `.any(port: 0)` to recover the
    /// kernel-assigned ephemeral port for a peer to send to. Valid for IPv4
    /// and IPv6 endpoints (see ``Kernel/Socket/Address/Storage``'s port
    /// reader).
    public borrowing func port() throws(Sockets.Error) -> UInt16 {
        let storage: Kernel.Socket.Address.Storage
        do throws(Kernel.Socket.Error) {
            storage = try Kernel.Socket.Name.local(descriptor).address
        } catch {
            throw .platform(error.code)
        }
        return storage._port
    }
}
