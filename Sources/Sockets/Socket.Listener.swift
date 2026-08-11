//
//  Socket.Listener.swift
//  swift-sockets
//

public import IO
public import Kernel

extension Socket {
    /// A cancellation gate over a concrete TCP listener.
    ///
    /// The listener retains the existing `Sockets.TCP.Listener`, including its
    /// IPv4/IPv6 factories, descriptor lifetime, and strategy pairing.
    /// Each successful ``accept(channel:)`` moves the supplied channel endpoint
    /// into the resulting ``Socket/Connection``.
    ///
    /// ## Lifetime
    ///
    /// `cancel()` prevents later accepts and is idempotent. It does not revoke
    /// a connection already returned and does not alter either direction of a
    /// channel already moved to one. `shutdown()` is the named terminal alias
    /// for that cancellation transition. Dropping the listener retains the
    /// concrete listener's descriptor-deinit close law.
    public actor Listener {
        private let socket: Sockets.TCP.Listener
        private var accepting = true

        /// Composes the canonical acceptance surface with a TCP listener.
        public init(socket: Sockets.TCP.Listener) {
            self.socket = socket
        }

        /// Binds an IPv4 listener using the existing blocking strategy.
        public static func blocking(
            address: Kernel.Socket.Address.IPv4,
            io: IO<Sockets.Capabilities>,
            backlog: Kernel.Socket.Backlog = .max
        ) throws(Socket.Error) -> Socket.Listener {
            Socket.Listener(
                socket: try Sockets.TCP.Listener.blocking(address: address, io: io, backlog: backlog)
            )
        }

        /// Binds an IPv6 listener using the existing blocking strategy.
        public static func blocking(
            address: Kernel.Socket.Address.IPv6,
            io: IO<Sockets.Capabilities>,
            backlog: Kernel.Socket.Backlog = .max
        ) throws(Socket.Error) -> Socket.Listener {
            Socket.Listener(
                socket: try Sockets.TCP.Listener.blocking(address: address, io: io, backlog: backlog)
            )
        }

        /// Binds an IPv4 listener using the existing reactive strategy.
        public static func reactive(
            address: Kernel.Socket.Address.IPv4,
            io: IO<Sockets.Capabilities>,
            backlog: Kernel.Socket.Backlog = .max
        ) throws(Socket.Error) -> Socket.Listener {
            Socket.Listener(
                socket: try Sockets.TCP.Listener.reactive(address: address, io: io, backlog: backlog)
            )
        }

        /// Binds an IPv6 listener using the existing reactive strategy.
        public static func reactive(
            address: Kernel.Socket.Address.IPv6,
            io: IO<Sockets.Capabilities>,
            backlog: Kernel.Socket.Backlog = .max
        ) throws(Socket.Error) -> Socket.Listener {
            Socket.Listener(
                socket: try Sockets.TCP.Listener.reactive(address: address, io: io, backlog: backlog)
            )
        }

        /// Accepts one connection and moves `channel` into it.
        public func accept(
            channel: consuming IO.Byte.Channel<Socket.Error>
        ) async throws(Socket.Error) -> sending Socket.Connection {
            guard accepting else { throw .cancelled }
            let connection = try await socket.accept()
            guard accepting else {
                await connection.close()
                throw .cancelled
            }
            return Socket.Connection(socket: consume connection, channel: consume channel)
        }

        /// Prevents later accepts without disturbing accepted connections.
        public func cancel() {
            accepting = false
        }

        /// Performs the listener's terminal acceptance transition.
        public func shutdown() {
            cancel()
        }
    }
}
