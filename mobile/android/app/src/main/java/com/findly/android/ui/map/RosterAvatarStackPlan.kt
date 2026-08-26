package com.findly.android.ui.map

/**
 * specs/010-app-shell-and-screen-ux.md §3.1 (normative — the FindlyBottomSheet minimized detent's
 * content list; HANDOFF.md:151 lists "avatar stack" on equal footing with grabber/title/summary/
 * Locate-now, and 010 deliberately kept it while dropping the handoff's "Drag up for details"
 * hint — a curated inclusion, not an oversight). Pure decision of which members' initials to show
 * and how many overflow, shared by [com.findly.android.ui.map.MapScreen]'s `RosterHeader` and
 * [com.findly.android.ui.groups.GroupMapScreen]'s `GroupRosterHeader` — both already carry
 * `displayName` (no new data needed), and this reuses the same short-label convention as
 * `GoogleMapRenderer.kt`'s marker-bubble `initialsFor` (duplicated rather than exposed from that
 * file, which keeps it `private`).
 */
object RosterAvatarStackPlan {
    const val MAX_VISIBLE = 4

    data class Plan(val visibleInitials: List<String>, val overflowCount: Int)

    // RED-before-GREEN placeholder (devloop/A34 review fix): deliberately wrong — always empty,
    // no overflow — so RosterAvatarStackPlanTest fails for a real assertion reason before the
    // real logic lands.
    fun compute(displayNames: List<String>, maxVisible: Int = MAX_VISIBLE): Plan = Plan(emptyList(), 0)

    fun initialsFor(displayName: String): String = "XX"
}
