# ``Sockets``

@Metadata {
    @DisplayName("Sockets")
    @TitleHeading("Swift Foundations")
}

Sockets provides descriptor-owning TCP and UDP endpoints. The base module owns
socket lifecycle and strategy selection; `Sockets Byte Channel` composes its
streaming byte-chunk integration as a separate consumer choice.

TCP listeners compose `IO<Sockets.TCP.Listener.Capabilities>`. Event admission
publishes cancellation and linear physical-completion ownership before the
listener actor suspends. Release rejects new accepts, cancels and joins the
live accept, then closes the listening descriptor exactly once. A blocking
listener strategy is intentionally unavailable because it has no portable
interrupt-and-wake law.

## Topics

### TCP and UDP

- ``Sockets/TCP/Connection``
- ``Sockets/TCP/Listener``
- ``Sockets/TCP/Listener/Capabilities``
- ``Sockets/TCP/Accepted``
- ``Sockets/UDP/Endpoint``
