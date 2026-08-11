//
//  Sockets.swift
//  swift-sockets
//
//  Root namespace for the Sockets domain package.
//
//  Socket-specific ergonomics (half-close, shutdown state, address parsing,
//  bind/listen/setsockopt, TCP connection management, UDP datagrams, DNS
//  resolution) live here. swift-sockets composes the
//  generic `IO<Capabilities>` bundle from swift-io-primitives with its own
//  ``Sockets/Capabilities`` and per-strategy factories; the strategy
//  runtimes (reactor / proactor actors) live in its strategy owner.
//

/// Root namespace for the Sockets domain package.
///
/// Groups the types that parameterize the generic `IO` bundle for the
/// sockets domain: ``Sockets/Capabilities`` (what operations exist),
/// ``Sockets/Error`` (the error domain), and the per-strategy factories
/// (`IO<Sockets.Capabilities>.blocking()` and `.events()`); a completions /
/// proactor factory remains future work. The TCP endpoints live under
/// ``Sockets/TCP``.
public enum Sockets {}
