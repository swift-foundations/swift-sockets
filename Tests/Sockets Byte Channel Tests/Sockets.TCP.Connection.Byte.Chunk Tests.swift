import Byte_Chunk
import Sockets_Byte_Channel
import Testing

@Suite struct `Sockets Byte Channel Tests` {
    @Test func `chunk maximum carries byte-count units`() {
        let maximum: Index<Byte>.Count = .zero
        #expect(maximum == .zero)
    }

    @Test func `pump static surface carries a typed injected failure and byte maximum`() {
        _ = PumpStaticCoverage.pump
    }
}

private enum PumpStaticCoverage {
    static func pump(
        connection: consuming Sockets.TCP.Connection,
        channel: consuming Byte.Channel<Sockets.Error>,
        maximum: Index<Byte>.Count,
        failure: @escaping @Sendable (Sockets.Error) -> Sockets.Error
    ) -> sending Sockets.TCP.Connection.Pump<Sockets.Error> {
        connection.pump(consume channel, maximum: maximum, failure: failure)
    }
}
