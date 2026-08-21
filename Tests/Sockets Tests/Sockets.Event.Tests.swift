import Testing

@testable import Sockets

extension Sockets.Event {

    @Suite(
        .serialized,
        .disabled(
            if: Toolchain.hasTaggedMetadataSIGSEGV,
            "Catalog §A9: swift-kernel's zero-registration Source.close reproducer crashes on Swift <6.4"
        )
    )
    struct Tests {}
}
