package com.findly.android.ui.map

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.findly.android.ui.groups.GroupMapMemberUi

/**
 * Abstraction over the actual map-tile view (A2 task brief: "put the actual map-tile view behind
 * a `MapRenderer` interface with a stub/placeholder implementation now"). [GoogleMapRenderer] is
 * the real Google Maps SDK implementation (A12) wired at
 * [com.findly.android.AppContainer]'s composition root; [PlaceholderMapRenderer] remains as a
 * lightweight fallback used by Compose previews/tests (no real projection, no Maps SDK view). A
 * real tile renderer needs an API key that only exists once H1 (`docs/azure-setup.md`)
 * provisions one — see `config/AppConfig.kt`'s `mapsApiKey`, sourced from a
 * gitignored/config-injected Gradle property, never committed
 * (docs/security-review-checklist.md §5) — but [GoogleMapRenderer] builds and runs fine with an
 * empty key too (it simply renders a tile-less grey map), the same "degrade gracefully without
 * secrets" seam every other H1-waived dependency in this codebase uses
 * ([com.findly.android.auth.AuthProvider], [com.findly.android.push.PushTokenProvider]).
 *
 * Markers and the roster list are always rendered through `ui/designsystem` components
 * ([com.findly.android.ui.designsystem.components.FindlyMapMarkerBubble]) regardless of which
 * [MapRenderer] is installed, so the map stays design-swappable even after a real tile SDK lands.
 *
 * A5 addition (specs/003-android-client.md §12.2): [RenderGroup] reuses this same seam for
 * `GroupMapScreen` — "rendered through the same `MapRenderer` seam" per spec — rather than a
 * second renderer interface, so a future real tile SDK only ever needs one implementation wired
 * in [com.findly.android.AppContainer]. It is a **distinctly-named** method, not a `Render`
 * overload: `List<RosterMemberUi>` and `List<GroupMapMemberUi>` erase to the same JVM signature
 * (`List`), so two same-named methods differing only in that generic parameter would be a
 * platform declaration clash, not a valid overload.
 */
interface MapRenderer {
    @Composable
    fun Render(members: List<RosterMemberUi>, modifier: Modifier)

    /** specs/005-temporary-groups.md §3 — position-only: no device/battery fields anywhere in
     * [GroupMapMemberUi], unlike [RosterMemberUi]'s [RosterDeviceUi] children. */
    @Composable
    fun RenderGroup(members: List<GroupMapMemberUi>, modifier: Modifier)
}
