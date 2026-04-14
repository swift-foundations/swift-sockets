//
//  Sockets.swift
//  swift-sockets
//
//  Root namespace for the Sockets domain package.
//
//  Socket-specific ergonomics (half-close, split into reader/writer, shutdown
//  state, address parsing, bind/listen/setsockopt, TCP connection management,
//  UDP datagrams, DNS resolution) live here. swift-sockets builds on top of
//  swift-io's domain-agnostic I/O witness over `Kernel.Descriptor` and — for
//  future events/completions strategies — the reactor and proactor runtimes
//  retained inside swift-io pending their Phase 2 refactor.
//
//  See swift-io/Research/io-architecture.md v1.1 for the layering.
//

/// Root namespace for the Sockets domain package.
///
/// Phase 1 holds only the migrated `Sockets.Error` type. Socket-specific
/// consumer types (`IO.Event.Channel*`, `IO.Completion.Channel*`) migrate
/// into this namespace during Phase 2 when the events/completions witness
/// factories are introduced on swift-io's side.
public enum Sockets {}
