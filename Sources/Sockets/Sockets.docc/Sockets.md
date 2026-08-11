# ``Sockets``

@Metadata {
    @DisplayName("Sockets")
    @TitleHeading("Swift Foundations")
}

Sockets provides descriptor-owning TCP and UDP endpoints. The base module owns
socket lifecycle and strategy selection; `Sockets Byte Channel` composes its
streaming byte-chunk integration as a separate consumer choice.

## Topics

### TCP and UDP

- ``Sockets/TCP/Connection``
- ``Sockets/TCP/Listener``
- ``Sockets/UDP/Endpoint``
