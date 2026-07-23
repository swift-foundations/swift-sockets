//
//  Toolchain.swift
//  swift-sockets
//

/// Toolchain capability gate for catalog §A9's `Tagged` metadata SIGSEGV.
///
/// Every real-reactor fixture eventually destroys its `Kernel.Event.Source`.
/// The source's `Driver._close` performs the first metadata-forcing operation
/// on its `Tagged`-keyed registry: `registry.removeAll(keepingCapacity: false)`.
/// The canonical swift-kernel construct+close reproducer proves this crashes
/// on Swift 6.3.x with zero registrations and a synthetic no-op driver, before
/// any socket or descriptor lifecycle can contribute.
///
/// Catalog §A9 (`swift-institute/Research/swift-compiler-bug-catalog.md`) records
/// incomplete Swift 6.3 `SuppressedAssociatedTypes` code generation: malformed
/// emitted type metadata yields a null lookup result and a dereference at
/// `+0x10`. The fix travels with Swift 6.4+ compiler binaries; there is no
/// Institute-side production workaround. A suite-level `.disabled(if:)` is
/// required because the SIGSEGV kills the runner before `withKnownIssue` can
/// record the failure.
enum Toolchain {}

extension Toolchain {
    /// `true` where real-reactor teardown triggers catalog §A9.
    static var hasTaggedMetadataSIGSEGV: Bool {
        #if compiler(<6.4)
        return true
        #else
        return false
        #endif
    }
}
