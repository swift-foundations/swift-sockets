# TCP listener source laws

These fixtures record compile-time ownership and availability laws. They are
source evidence only under the transaction moratorium.

- `positive-release-shape.swift.fixture` records the downstream-compatible
  nonthrowing async release closure.
- `positive-move-only-accepted.swift.fixture` records linear accepted-result
  transfer.
- `negative-blocking-listener.swift.fixture` records that no uninterruptible
  blocking listener factory exists.
- `negative-repeat-accepted.swift.fixture` records that accepted ownership
  cannot be copied into two result consumers.

Runtime-shaped tests in `Sockets.TCP.Listener.Tests.BlockingIdleCPU.swift`
record pending-accept cancellation, post-release rejection, and repeated
release. They remain **UNVERIFIED** until the moratorium is lifted.
