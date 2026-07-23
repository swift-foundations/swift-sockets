//
//  Sockets.Event.Tests.swift
//  swift-sockets
//

import Testing

@testable import Sockets

extension Sockets.Event {
    /// Serialized real-reactor fixtures. Each test creates and shuts down its
    /// own polling actor and uses only local kernel sockets.
    @Suite(
        .serialized,
        .disabled(
            if: Toolchain.hasTaggedMetadataSIGSEGV,
            "Catalog §A9: swift-kernel's zero-registration Source.close reproducer crashes on Swift <6.4"
        )
    )
    struct Tests {}
}
