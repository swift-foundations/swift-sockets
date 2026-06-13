//
//  Sockets.swift
//  swift-sockets
//
//  Root namespace for the Sockets domain package.
//
//  Socket-specific ergonomics (half-close, split into reader/writer, shutdown
//  state, address parsing, bind/listen/setsockopt, TCP connection management,
//  UDP datagrams, DNS resolution) live here. swift-sockets composes the
//  generic `IO<Capabilities>` bundle from swift-io-primitives with its own
//  ``Sockets/Capabilities`` and per-strategy factories; the strategy
//  runtimes (reactor / proactor actors) live in swift-io.
//
//  See swift-io/Research/io-architecture.md for the layering and
//  swift-io-primitives' `IO.swift` for the per-(domain × strategy)
//  composition pattern.
//

/// Root namespace for the Sockets domain package.
///
/// Groups the types that parameterize the generic `IO` bundle for the
/// sockets domain: ``Sockets/Capabilities`` (what operations exist),
/// ``Sockets/Error`` (the error domain), and the per-strategy factories
/// (`IO<Sockets.Capabilities>.blocking()` for Phase 2A; events /
/// completions follow in Phase 2B / 2C). The TCP endpoints live under
/// ``Sockets/TCP``.
public enum Sockets {}
