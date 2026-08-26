import Foundation

/// specs/010-app-shell-and-screen-ux.md §1.2 — one item in `FindlyNavDrawer`'s list. `id` is a
/// stable, screen-agnostic string (never localized UI text) so `FindlyNavDrawer.onSelect(_:)` and
/// `LiveMapScreen`'s routing switch can key off it without any coupling to display copy.
public struct FindlyNavDrawerItem: Identifiable, Equatable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// Pure builder for the drawer's normative item list (010 §1.2): "Family map (current), History,
/// Geofences, Devices, Family, Invite someone (parents only), Groups, Privacy & data." Kept
/// separate from the presentational `FindlyNavDrawer` component so the list/order/gating logic is
/// unit-testable with no SwiftUI hosting at all (010 §10's "item list/order" checklist item).
public enum FindlyNavDrawerBuilder {
    public static func items(isParent: Bool) -> [FindlyNavDrawerItem] {
        var items = [
            FindlyNavDrawerItem(id: "familyMap", title: "Family map"),
            FindlyNavDrawerItem(id: "history", title: "History"),
            FindlyNavDrawerItem(id: "geofences", title: "Geofences"),
            FindlyNavDrawerItem(id: "devices", title: "Devices"),
            FindlyNavDrawerItem(id: "family", title: "Family"),
        ]
        if isParent {
            items.append(FindlyNavDrawerItem(id: "inviteSomeone", title: "Invite someone"))
        }
        items.append(contentsOf: [
            FindlyNavDrawerItem(id: "groups", title: "Groups"),
            FindlyNavDrawerItem(id: "privacyData", title: "Privacy & data"),
        ])
        return items
    }
}
