//
//  Socket.Connection.swift
//  swift-sockets
//

public import IO
public import Buffer_Primitives
public import Byte_Primitives
public import Kernel

extension Socket {
    /// A channel-facing TCP connection over a concrete descriptor owner.
    ///
    /// `inbound` is this connection's sole reader and `outbound` is its
    /// copyable writer. The caller supplies an ``IO/Byte/Channel`` endpoint;
    /// `IO.Byte.Channel.pair(capacity:)` wires its outbound half to the peer's
    /// inbound half and retains the channel package's backpressure,
    /// cancellation, and first-terminal-wins laws.
    ///
    /// The retained ``Sockets/TCP/Connection`` owns the descriptor and its
    /// strategy-specific system calls. The channel deliberately does not copy
    /// that implementation or invent a competing scheduler. A transport pump
    /// may bridge the two at the integration owner; this value makes the
    /// ownership boundary explicit.
    ///
    /// ## Lifetime
    ///
    /// `Connection` is `~Copyable`. Finishing `outbound` half-closes only the
    /// peer's inbound channel direction; finishing `inbound` rejects peer
    /// sends. Those actions do not close the descriptor. ``shutdown(how:)``
    /// forwards TCP's descriptor-level half-close. ``close()`` first closes
    /// both local channel directions, then consumes the descriptor owner.
    public struct Connection: ~Copyable, Sendable {
        /// The sole inbound byte reader for this endpoint.
        public var inbound: IO.Reader<Buffer.Slice<Byte_Primitives.Byte>, Socket.Error>

        /// The copyable outbound byte writer for this endpoint.
        public let outbound: IO.Writer<Buffer.Slice<Byte_Primitives.Byte>, Socket.Error>

        /// The retained concrete TCP descriptor owner.
        public let socket: Sockets.TCP.Connection

        /// Composes a canonical channel endpoint with a concrete TCP owner.
        public init(
            socket: consuming Sockets.TCP.Connection,
            channel: consuming IO.Byte.Channel<Socket.Error>
        ) {
            self.inbound = consume channel.inbound
            self.outbound = channel.outbound
            self.socket = socket
        }
    }
}

extension Socket.Connection {
    /// Connects to an IPv4 peer and moves `channel` into the result.
    public static func connect(
        to address: Kernel.Socket.Address.IPv4,
        io: IO<Sockets.Capabilities>,
        channel: consuming IO.Byte.Channel<Socket.Error>
    ) async throws(Socket.Error) -> sending Socket.Connection {
        let socket = try await Sockets.TCP.Connection.connect(to: address, io: io)
        return Socket.Connection(socket: consume socket, channel: consume channel)
    }

    /// Connects to an IPv6 peer and moves `channel` into the result.
    public static func connect(
        to address: Kernel.Socket.Address.IPv6,
        io: IO<Sockets.Capabilities>,
        channel: consuming IO.Byte.Channel<Socket.Error>
    ) async throws(Socket.Error) -> sending Socket.Connection {
        let socket = try await Sockets.TCP.Connection.connect(to: address, io: io)
        return Socket.Connection(socket: consume socket, channel: consume channel)
    }

    /// Applies TCP's descriptor-level half-close without terminating either
    /// channel direction. The connection remains usable in the opposite TCP
    /// direction until ``close()`` consumes it.
    public borrowing func shutdown(
        how: Kernel.Socket.Shutdown.How
    ) throws(Socket.Error) {
        try socket.shutdown(how: how)
    }

    /// Closes both channel directions and then consumes the TCP descriptor.
    ///
    /// This ordering rejects new peer sends before the locally exposed writer
    /// is finished, matching `IO.Channel.shutdown()`'s ordered shutdown law.
    public consuming func close() async {
        inbound.finish()
        outbound.finish()
        await socket.close()
    }
}
