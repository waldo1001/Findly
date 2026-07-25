import SwiftUI
#if canImport(MapKit)
import MapKit
#endif

/// specs/004-ios-client.md I2 (§5.2) — wraps the base map layer behind a small seam so it stays
/// swappable: a future map provider needs only a new conforming type, never a change to
/// `LiveMapViewModel`/`LiveMapScreen`. `AnyView` erasure keeps call sites simple (`any
/// MapRendering`, no associated-type generics leaking into the screen layer).
public protocol MapRendering {
    func makeMapView(region: Binding<MapRegion>, annotations: [MapAnnotationItem]) -> AnyView
}

#if canImport(MapKit)
/// The real base map — first-party MapKit (`Map`), no API key required. Gated behind
/// `canImport(MapKit)` so `FindlyKit` still `swift build`s on a host that lacks the framework;
/// annotations always render as the design-system `MapMarkerBubble`, never a raw MapKit pin.
public struct MapKitRendering: MapRendering {
    public init() {}

    public func makeMapView(region: Binding<MapRegion>, annotations: [MapAnnotationItem]) -> AnyView {
        let mkRegion = Binding<MKCoordinateRegion>(
            get: {
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: region.wrappedValue.centerLat, longitude: region.wrappedValue.centerLon),
                    span: MKCoordinateSpan(latitudeDelta: region.wrappedValue.spanLatDelta, longitudeDelta: region.wrappedValue.spanLonDelta)
                )
            },
            set: { newValue in
                region.wrappedValue = MapRegion(
                    centerLat: newValue.center.latitude, centerLon: newValue.center.longitude,
                    spanLatDelta: newValue.span.latitudeDelta, spanLonDelta: newValue.span.longitudeDelta
                )
            }
        )
        return AnyView(
            Map(coordinateRegion: mkRegion, annotationItems: annotations) { item in
                MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: item.lat, longitude: item.lon)) {
                    MapMarkerBubble(initials: item.initials, isStale: item.isStale)
                }
            }
        )
    }
}
#endif

/// Always-available fallback with no MapKit dependency at all — proof the abstraction is genuinely
/// swappable, and a renderer every host (incl. this CLT-only macOS session) can build and exercise
/// without any map framework.
public struct ListMapRendering: MapRendering {
    public init() {}

    public func makeMapView(region: Binding<MapRegion>, annotations: [MapAnnotationItem]) -> AnyView {
        AnyView(
            VStack {
                ForEach(annotations) { item in
                    MapMarkerBubble(initials: item.initials, isStale: item.isStale)
                }
            }
        )
    }
}
