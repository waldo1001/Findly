import Foundation

/// specs/004-ios-client.md I2 (001 §5.2) — a platform-agnostic map viewport, decoupled from
/// `MKCoordinateRegion` so a `MapRendering` implementation that doesn't use MapKit never needs to
/// import it — keeps the map-provider seam genuinely swappable.
public struct MapRegion: Equatable {
    public var centerLat: Double
    public var centerLon: Double
    public var spanLatDelta: Double
    public var spanLonDelta: Double

    public init(centerLat: Double, centerLon: Double, spanLatDelta: Double = 0.05, spanLonDelta: Double = 0.05) {
        self.centerLat = centerLat
        self.centerLon = centerLon
        self.spanLatDelta = spanLatDelta
        self.spanLonDelta = spanLonDelta
    }

    /// A reasonable default viewport before the first family fix arrives.
    public static let findlyDefault = MapRegion(centerLat: 51.0543, centerLon: 3.7174)
}

/// One family device with a known position (001 §5.2) — `MapMarkerBubble`-ready. Devices with no
/// fix yet (`lat`/`lon` both `nil`) never produce an annotation; they still appear in the roster
/// list instead (rendered by `LiveMapScreen`, not the map layer).
public struct MapAnnotationItem: Identifiable, Equatable {
    public let id: String
    public let lat: Double
    public let lon: Double
    public let initials: String
    public let isStale: Bool

    public init(id: String, lat: Double, lon: Double, initials: String, isStale: Bool) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.initials = initials
        self.isStale = isStale
    }
}
