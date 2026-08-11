# ``Sockets``

@Metadata {
    @DisplayName("Sockets")
    @TitleHeading("Swift Foundations")
}

Sockets provides descriptor-owning TCP and UDP endpoints together with the
canonical channel-facing ``Socket`` vocabulary.

`Socket.Connection` composes one concrete ``Sockets/TCP/Connection`` with an
``IO/Byte/Channel`` endpoint. The channel owns bounded byte flow and its
directional terminal laws; TCP owns descriptor lifetime and descriptor-level
half-close. `Socket.Listener` composes acceptance with a supplied channel
endpoint for every returned connection. `Socket.Datagram` preserves one UDP
message boundary and its source/destination metadata without owning a socket.

The existing `Sockets.TCP` and `Sockets.UDP` surfaces remain available for
source compatibility, including current TLS composition.

## Topics

### Canonical socket surface

- ``Socket/Connection``
- ``Socket/Listener``
- ``Socket/Datagram``
