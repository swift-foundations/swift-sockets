//
//  Sockets.Error.Registration.swift
//  swift-sockets
//

extension Sockets.Error {
    /// Socket descriptor registration lifecycle state.
    public enum Registration: Sendable, Equatable {
        /// The descriptor already has a reactor registration.
        case duplicate

        /// No registration exists for the descriptor.
        case missing

        /// The descriptor was deregistered while work was pending.
        case removed
    }
}
