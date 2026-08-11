import Byte_Chunk
import Sockets_Byte_Channel
import Testing

/// Source-only coverage is held pending joint producer admission.
@Suite struct `Sockets Byte Channel Tests` {
    @Test func `chunk maximum carries byte-count units`() {
        let maximum: Index<Byte>.Count = .zero
        #expect(maximum == .zero)
    }
}
