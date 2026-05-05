import Foundation
import IOKit.pwr_mgt

/// Wraps an `IOPMAssertion` that prevents user-idle system sleep.
/// The kernel auto-releases assertions when the owning process exits, so
/// even a hard crash will not leak.
final class SleepAssertion {
    private static let name = "GPSMock: keep system awake while open" as CFString

    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var held = false

    func enable() {
        guard !held else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.name,
            &assertionID
        )
        if result == kIOReturnSuccess {
            held = true
        }
    }

    func disable() {
        guard held else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(0)
        held = false
    }

    deinit {
        disable()
    }
}
