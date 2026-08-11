public import Byte_Chunk
public import Sockets

extension Sockets.TCP.Connection {
    /// Reads at most `maximum` bytes after readiness, returning `nil` at EOF.
    /// The output view exists only during the synchronous kernel attempt.
    public borrowing func read(
        maximum: Index<Byte>.Count
    ) async throws(Sockets.Error) -> sending Byte.Chunk? {
        var input = Byte.Chunk.Input(capacity: maximum)
        if maximum == .zero { return consume input.finish() }

        while true {
            try await io.ready(from: descriptor, interest: .read)
            do {
                let count = try read(into: &input.outputSpan)
                guard count != 0 else { return nil }
                return consume input.finish()
            } catch .wouldBlock {
                continue
            }
        }
    }

    /// Writes every byte from `chunk`, retrying partial non-blocking attempts.
    /// No borrowed view crosses an asynchronous suspension point.
    public borrowing func write(
        _ chunk: consuming Byte.Chunk
    ) async throws(Sockets.Error) {
        if chunk.count == .zero { return }

        var written = 0
        while true {
            try await io.ready(from: descriptor, interest: .write)
            let remaining = chunk.span.dropFirst(written)
            guard !remaining.isEmpty else { return }
            do {
                written += try write(from: remaining)
            } catch .wouldBlock {
                continue
            }
        }
    }
}
