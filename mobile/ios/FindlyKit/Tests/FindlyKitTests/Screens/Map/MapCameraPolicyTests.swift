import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §3.4 (normative) — `MapCameraPolicy.target` is the
/// platform/SDK-agnostic camera decision (mirrors Android's `MapCamera.target`,
/// `MapCamera.kt`): pure Swift logic, no MapKit dependency, exercised on any host.
@MainActor
struct MapCameraPolicyTargetTests {

    @Test func noPointsYieldsTheCalmZoomedOutDefault_neverNullIsland() {
        let target = MapCameraPolicy.target(points: [])
        #expect(target == .defaultRegion(lat: MapCameraPolicy.defaultLat, lon: MapCameraPolicy.defaultLon, zoom: MapCameraPolicy.defaultZoom))
    }

    @Test func aSinglePointCentersOnItAtACloseZoom() {
        let target = MapCameraPolicy.target(points: [MapGeoPoint(lat: 51.0543, lon: 3.7174)])
        #expect(target == .center(lat: 51.0543, lon: 3.7174, zoom: MapCameraPolicy.singlePointZoom))
    }

    @Test func duplicateIdenticalPointsCollapseToCenter_notAZeroAreaBounds() {
        let target = MapCameraPolicy.target(points: [
            MapGeoPoint(lat: 51.0543, lon: 3.7174),
            MapGeoPoint(lat: 51.0543, lon: 3.7174),
            MapGeoPoint(lat: 51.0543, lon: 3.7174),
        ])
        #expect(target == .center(lat: 51.0543, lon: 3.7174, zoom: MapCameraPolicy.singlePointZoom))
    }

    @Test func twoDistinctPointsYieldBoundsSpanningBoth() {
        let target = MapCameraPolicy.target(points: [MapGeoPoint(lat: 51.20, lon: 3.90), MapGeoPoint(lat: 50.85, lon: 3.20)])
        guard case .bounds(let south, let north, let west, let east, let padding) = target else {
            Issue.record("expected .bounds, got \(target)")
            return
        }
        #expect(south == 50.85)
        #expect(north == 51.20)
        #expect(west == 3.20)
        #expect(east == 3.90)
        #expect(padding == MapCameraPolicy.boundsPaddingPt)
    }

    @Test func boundsCorrectlySpansNegativeCoordinates() {
        let target = MapCameraPolicy.target(points: [MapGeoPoint(lat: -33.87, lon: 151.21), MapGeoPoint(lat: -37.81, lon: 144.96)])
        guard case .bounds(let south, let north, let west, let east, _) = target else {
            Issue.record("expected .bounds, got \(target)")
            return
        }
        #expect(south == -37.81)
        #expect(north == -33.87)
        #expect(west == 144.96)
        #expect(east == 151.21)
    }

    @Test func threeOrMoreDistinctPointsStillYieldOneBoundsCoveringEveryPoint() {
        let target = MapCameraPolicy.target(points: [MapGeoPoint(lat: 51.0, lon: 3.5), MapGeoPoint(lat: 51.2, lon: 3.9), MapGeoPoint(lat: 50.9, lon: 3.6)])
        guard case .bounds(let south, let north, let west, let east, _) = target else {
            Issue.record("expected .bounds, got \(target)")
            return
        }
        #expect(south == 50.9)
        #expect(north == 51.2)
        #expect(west == 3.5)
        #expect(east == 3.9)
    }

    @Test func pointsAFewMetresApartNeverCollapseIntoOne() {
        let target = MapCameraPolicy.target(points: [MapGeoPoint(lat: 51.05430, lon: 3.71740), MapGeoPoint(lat: 51.05431, lon: 3.71741)])
        guard case .bounds(let south, let north, _, _, _) = target else {
            Issue.record("expected .bounds, got \(target)")
            return
        }
        #expect(south == 51.05430)
        #expect(north == 51.05431)
    }
}

/// specs/010 §3.4 — WHEN the camera policy re-runs, as pure state independent of
/// `MapCameraPolicy.target` (which decides WHERE). This is the regression this task exists to
/// prevent: today every marker-set change yanks the camera; §10's test checklist requires proving
/// "a refresh with changed points yields *no* camera command" — see
/// `refreshAfterInitialLoad_neverRunsAgain_evenThoughThePointSetChanged` below.
@MainActor
struct MapCameraPolicyWhenTests {

    @Test func theVeryFirstLoad_runs_evenWithZeroLocatedPoints() {
        let decision = MapCameraPolicy.shouldRunOnLoadOrRefresh(state: .initial, hasPoints: false)
        #expect(decision)
    }

    @Test func theVeryFirstLoad_runs_whenItAlreadyHasPoints() {
        let decision = MapCameraPolicy.shouldRunOnLoadOrRefresh(state: .initial, hasPoints: true)
        #expect(decision)
    }

    @Test func aRefreshAfterAnEmptyFirstLoad_stillEmpty_doesNotRun() {
        let afterFirstLoad = MapCameraPolicy.nextState(state: .initial, hasPoints: false)
        let decision = MapCameraPolicy.shouldRunOnLoadOrRefresh(state: afterFirstLoad, hasPoints: false)
        #expect(!decision)
    }

    @Test func theFirstRefreshThatBringsTheFirstEverPointIn_fromAZeroPointOpen_runsOnce() {
        let afterEmptyFirstLoad = MapCameraPolicy.nextState(state: .initial, hasPoints: false)
        let decision = MapCameraPolicy.shouldRunOnLoadOrRefresh(state: afterEmptyFirstLoad, hasPoints: true)
        #expect(decision)
    }

    @Test func refreshAfterInitialLoad_neverRunsAgain_evenThoughThePointSetChanged() {
        // First load already had a point — the steady state every subsequent poll/manual refresh
        // lands in.
        let steadyState = MapCameraPolicy.nextState(state: .initial, hasPoints: true)

        // A refresh that changes the marker set (still non-empty, just different/more points)
        // MUST NOT re-run the policy — the exact bug 010 §3.4 exists to fix.
        let decision = MapCameraPolicy.shouldRunOnLoadOrRefresh(state: steadyState, hasPoints: true)
        #expect(!decision)
    }

    @Test func refreshAfterInitialLoad_neverRunsAgain_evenIfPointsDisappear() {
        let steadyState = MapCameraPolicy.nextState(state: .initial, hasPoints: true)
        let decision = MapCameraPolicy.shouldRunOnLoadOrRefresh(state: steadyState, hasPoints: false)
        #expect(!decision)
    }

    @Test func nextState_marksHasRunInitialTrue_andRemembersEverHavingHadAPoint() {
        let state = MapCameraPolicy.nextState(state: .initial, hasPoints: true)
        #expect(state == MapCameraPolicyState(hasRunInitial: true, hadAnyPoint: true))
    }

    @Test func hadAnyPoint_staysTrueOnceSet_evenAcrossALaterEmptyRefresh() {
        let withPoint = MapCameraPolicy.nextState(state: .initial, hasPoints: true)
        let afterEmptyRefresh = MapCameraPolicy.nextState(state: withPoint, hasPoints: false)
        #expect(afterEmptyRefresh.hadAnyPoint)
    }
}

/// specs/010 §3.5 / §10 "Freshest-device resolution": newest `recordedAt` among located devices
/// wins; devices without a fix are never chosen.
@MainActor
struct MapCameraPolicyFreshestDeviceTests {

    private func device(id: String, recordedAt: String?, hasLocation: Bool = true) -> DeviceLocation {
        DeviceLocation(
            deviceId: id, deviceName: "Device \(id)",
            lat: hasLocation ? 51.0 : nil, lon: hasLocation ? 3.7 : nil,
            accuracyM: hasLocation ? 10 : nil,
            recordedAt: recordedAt, receivedAt: recordedAt,
            batteryPct: nil, source: hasLocation ? .periodic : nil,
            trackingEnabled: true, syncIntervalMinutes: 15, isStale: false
        )
    }

    @Test func freshestDevice_isTheOneWithTheNewestRecordedAt() {
        let older = device(id: "d1", recordedAt: "2026-08-26T09:00:00Z")
        let newer = device(id: "d2", recordedAt: "2026-08-26T10:30:00Z")
        let result = MapCameraPolicy.freshestLocatedDevice(devices: [older, newer])
        #expect(result?.deviceId == "d2")
    }

    @Test func devicesWithoutAFix_areNeverChosen_evenIfPresentInTheList() {
        let noFix = device(id: "d1", recordedAt: nil, hasLocation: false)
        let withFix = device(id: "d2", recordedAt: "2026-08-26T09:00:00Z")
        let result = MapCameraPolicy.freshestLocatedDevice(devices: [noFix, withFix])
        #expect(result?.deviceId == "d2")
    }

    @Test func noLocatedDeviceAnywhere_yieldsNil_notACrash() {
        let noFix = device(id: "d1", recordedAt: nil, hasLocation: false)
        let result = MapCameraPolicy.freshestLocatedDevice(devices: [noFix])
        #expect(result == nil)
    }

    @Test func anEmptyDeviceList_yieldsNil() {
        #expect(MapCameraPolicy.freshestLocatedDevice(devices: []) == nil)
    }
}
