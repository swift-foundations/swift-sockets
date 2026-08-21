import IO
import Kernel
import Sockets
import Testing

extension Sockets.TCP.Listener {

    @Suite(.serialized)
    enum Tests {}
}

extension Sockets.TCP.Listener.Tests {

    enum Strategy: Sendable, CaseIterable {
        case blocking
        case reactive
    }
}

extension Sockets.TCP.Listener.Tests.Strategy {

    func makeIO() -> IO<Sockets.Capabilities> {
        switch self {
        case .blocking: return .blocking()
        case .reactive: return makeReactiveIO()
        }
    }

    static func makeServer(
        _ strategy: Self
    ) async throws -> (IO<Sockets.Capabilities>, Sockets.TCP.Listener) {
        let io = strategy.makeIO()
        let listener: Sockets.TCP.Listener
        switch strategy {
        case .blocking:
            listener = try Sockets.TCP.Listener.blocking(
                address: Kernel.Socket.Address.IPv4.loopback(port: 0),
                io: io
            )

        case .reactive:
            listener = try Sockets.TCP.Listener.reactive(
                address: Kernel.Socket.Address.IPv4.loopback(port: 0),
                io: io
            )
        }
        return (io, listener)
    }
}
