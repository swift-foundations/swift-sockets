//
//  Socket.Tests.Static.swift
//  swift-sockets
//
//  Source-level API coverage for TX-N2. These declarations deliberately need
//  no kernel activity: the programme's moratorium leaves runtime verification
//  to the post-merge cleanup successor.
//

import Buffer_Primitives
import Byte_Primitives
import IO
import Kernel
import Sockets

private enum SocketStaticCoverage {
    static func connection(
        socket: consuming Sockets.TCP.Connection,
        channel: consuming IO.Byte.Channel<Socket.Error>
    ) -> sending Socket.Connection {
        Socket.Connection(socket: consume socket, channel: consume channel)
    }

    static func listener(
        socket: Sockets.TCP.Listener
    ) -> Socket.Listener {
        Socket.Listener(socket: socket)
    }

    static func ipv4Listener(
        address: Kernel.Socket.Address.IPv4,
        io: IO<Sockets.Capabilities>
    ) throws(Sockets.Error) -> Socket.Listener {
        try Socket.Listener.blocking(address: address, io: io)
    }

    static func ipv6Listener(
        address: Kernel.Socket.Address.IPv6,
        io: IO<Sockets.Capabilities>
    ) throws(Sockets.Error) -> Socket.Listener {
        try Socket.Listener.blocking(address: address, io: io)
    }

    static func datagram(
        payload: consuming Buffer.Slice<Byte_Primitives.Byte>,
        source: Socket.Datagram.Address,
        destination: Socket.Datagram.Address
    ) -> sending Socket.Datagram {
        Socket.Datagram(
            payload: consume payload,
            source: source,
            destination: destination
        )
    }

    static func shutdown(
        listener: Socket.Listener
    ) async {
        await listener.cancel()
        await listener.shutdown()
    }
}
