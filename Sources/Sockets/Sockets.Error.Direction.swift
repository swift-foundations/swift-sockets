//
//  Sockets.Error.Direction.swift
//  swift-sockets
//

extension Sockets.Error {
    /// Half of a full-duplex socket operation.
    public enum Direction: Sendable, Equatable {
        case read
        case write
    }
}
