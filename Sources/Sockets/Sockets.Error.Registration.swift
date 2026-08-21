extension Sockets.Error {

    public enum Registration: Sendable, Equatable {

        case duplicate

        case missing

        case removed
    }
}
