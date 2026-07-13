//
//  Sockets.UDP.swift
//  swift-sockets
//

extension Sockets {
    /// UDP socket domain.
    ///
    /// Provides the connectionless datagram endpoint for UDP:
    /// ``Sockets/UDP/Endpoint`` owns a bound `.datagram` descriptor and
    /// sends / receives datagrams through the shared `IO<Sockets.Capabilities>`
    /// surface. Unlike ``Sockets/TCP`` there is no passive/connected split —
    /// a single bound endpoint both sends (to an explicit address) and
    /// receives (reporting each datagram's sender).
    ///
    /// Datagram I/O composes with the blocking strategy the same way the
    /// TCP endpoints do — `sendto(2)` / `recvfrom(2)` run on the
    /// `IO<Sockets.Capabilities>`'s executor thread via actor isolation.
    public enum UDP {}
}
