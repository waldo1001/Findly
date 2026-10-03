import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §7 "Battery level — how `batteryPct` is read" (I57), specs/001 §1.4
/// (`batteryPct`: required integer 0-100 on every fix, no "unknown" value). Every iPhone used to
/// report `100` on every fix because the app wiring never supplied a battery source; the real
/// source is `UIDevice.batteryLevel` (a `Float`, 0.0-1.0, `-1.0` when unknown). This is the pure,
/// UIKit-free mapping — testable on any host (`swift test` runs under AppKit, specs/004 §2.3) —
/// whose one real caller is the UIKit-backed reader in the app wiring.
struct BatteryPercentTests {

    // MARK: Unknown level -> the historic placeholder 100

    @Test func unknownLevel_minusOne_mapsToTheHundredPlaceholder() {
        // `-1.0` is what UIDevice reports with monitoring off, and always on the Simulator.
        #expect(BatteryPercent.from(uiDeviceLevel: -1.0) == 100)
    }

    @Test func anyOtherNegativeLevel_isTreatedAsUnknown() {
        #expect(BatteryPercent.from(uiDeviceLevel: -0.5) == 100)
        #expect(BatteryPercent.from(uiDeviceLevel: -0.01) == 100)
        #expect(BatteryPercent.from(uiDeviceLevel: -100) == 100)
        #expect(BatteryPercent.from(uiDeviceLevel: -.infinity) == 100)
    }

    @Test func notANumber_isTreatedAsUnknown_andDoesNotTrap() {
        // `Int(Float.nan)` traps; the mapping must never reach it.
        #expect(BatteryPercent.from(uiDeviceLevel: .nan) == 100)
    }

    // MARK: Boundaries

    @Test func empty_mapsToZero_notToUnknown() {
        // A genuinely empty battery (0.0) is a real reading, distinct from the unknown -1.0.
        #expect(BatteryPercent.from(uiDeviceLevel: 0.0) == 0)
    }

    @Test func full_mapsToOneHundred() {
        #expect(BatteryPercent.from(uiDeviceLevel: 1.0) == 100)
    }

    @Test func aboveOne_clampsToOneHundred() {
        #expect(BatteryPercent.from(uiDeviceLevel: 1.01) == 100)
        #expect(BatteryPercent.from(uiDeviceLevel: 2.0) == 100)
        #expect(BatteryPercent.from(uiDeviceLevel: .infinity) == 100)
    }

    // MARK: The truncation trap — round, never truncate

    // Each input below is one a TRUNCATING implementation (`Int(level * 100)`) gets one percent low
    // — verified in Float arithmetic: `Float(0.53) * 100` == 52.999996 and `Float(0.59) * 100` ==
    // 58.999996, while `Float(0.35) * 100` and `Float(0.05) * 100` are exactly 35.0 / 5.0 (so those
    // two are NOT traps; their `nextDown` neighbours are).

    @Test func pointFiveThree_mapsToFiftyThree_notFiftyTwo() {
        #expect(BatteryPercent.from(uiDeviceLevel: 0.53) == 53)
    }

    @Test func pointFiveNine_mapsToFiftyNine_notFiftyEight() {
        #expect(BatteryPercent.from(uiDeviceLevel: 0.59) == 59)
    }

    @Test func oneUlpBelowAWholePercent_stillMapsToThatPercent() {
        // An OS-supplied Float can sit one ulp low (34.999996 / 4.9999995 after the multiply).
        #expect(BatteryPercent.from(uiDeviceLevel: Float(0.35).nextDown) == 35)
        #expect(BatteryPercent.from(uiDeviceLevel: Float(0.05).nextDown) == 5)
    }

    @Test func everyFivePercentStep_mapsToItsExactPercent() {
        // iOS 17+ reports the level in 5 % steps (iOS 16 in 1 % steps — see the whole-percent sweep
        // below); every step must map to its exact percent. Plain correctness, not a truncation trap.
        for percent in stride(from: 0, through: 100, by: 5) {
            let level = Float(percent) / 100
            #expect(BatteryPercent.from(uiDeviceLevel: level) == percent, "step \(percent) % (level \(level))")
        }
    }

    @Test func everyWholePercent_roundTripsExactly() {
        // The 1 % granularity iOS 16 reports. Over `Float(p) / 100`, a truncating implementation
        // fails only at 53 and 59 — so this sweep catches it too, but the two named tests above
        // pin the failure down by name.
        for percent in 0...100 {
            let level = Float(percent) / 100
            #expect(BatteryPercent.from(uiDeviceLevel: level) == percent, "\(percent) % (level \(level))")
        }
    }

    @Test func inBetweenValues_roundToTheNearestPercent() {
        #expect(BatteryPercent.from(uiDeviceLevel: 0.344) == 34)
        #expect(BatteryPercent.from(uiDeviceLevel: 0.346) == 35)
        #expect(BatteryPercent.from(uiDeviceLevel: 0.004) == 0)
        #expect(BatteryPercent.from(uiDeviceLevel: 0.996) == 100)
    }

    // MARK: The contract the backend enforces

    @Test func result_isAlwaysWithinTheBackendRange() {
        let samples: [Float] = [-.infinity, -2, -1, -0.0001, 0, 0.0001, 0.5, 0.9999, 1, 1.0001, 7, .infinity, .nan]
        for level in samples {
            let pct = BatteryPercent.from(uiDeviceLevel: level)
            #expect((0...100).contains(pct), "level \(level) -> \(pct)")
        }
    }
}
