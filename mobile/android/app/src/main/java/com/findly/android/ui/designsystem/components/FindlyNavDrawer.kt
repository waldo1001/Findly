package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.DrawerState
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * The 010-app-shell-and-screen-ux.md §1.2 navigation drawer's destinations, in the spec's
 * normative order — the ☰ button on the Family Map (the only screen that renders it, §1.2) opens
 * this drawer; selecting an item closes it and **pushes** that destination onto the existing
 * stack (never replaces the map root).
 */
enum class FindlyNavDrawerDestination { FamilyMap, History, Geofences, Devices, Family, InviteSomeone, Groups, PrivacyAndData }

/** One rendered drawer row. [selected] marks the current screen (only ever [FindlyNavDrawerDestination.FamilyMap]
 * while the drawer only opens from the map root, §1.2). */
data class FindlyNavDrawerItem(val destination: FindlyNavDrawerDestination, val label: String, val selected: Boolean = false)

/**
 * The pure item-list builder behind [FindlyNavDrawer] — no Compose import, unit-testable with
 * plain JUnit (specs/010 §10: "Drawer: parent-gating of 'Invite someone'; item list/order").
 * "Invite someone" is rendered **only** for `myRole == "parent"` (010 §1.2) — gated by omitting it
 * from the list entirely, not by disabling a visible row.
 */
object FindlyNavDrawerItems {
    fun build(
        isParent: Boolean,
        selected: FindlyNavDrawerDestination = FindlyNavDrawerDestination.FamilyMap,
    ): List<FindlyNavDrawerItem> {
        val labels = buildList {
            add(FindlyNavDrawerDestination.FamilyMap to "Family map")
            add(FindlyNavDrawerDestination.History to "History")
            add(FindlyNavDrawerDestination.Geofences to "Geofences")
            add(FindlyNavDrawerDestination.Devices to "Devices")
            add(FindlyNavDrawerDestination.Family to "Family")
            if (isParent) add(FindlyNavDrawerDestination.InviteSomeone to "Invite someone")
            add(FindlyNavDrawerDestination.Groups to "Groups")
            add(FindlyNavDrawerDestination.PrivacyAndData to "Privacy & data")
        }
        return labels.map { (destination, label) -> FindlyNavDrawerItem(destination, label, selected = destination == selected) }
    }
}

private val DrawerHeaderTitleStyle = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
private val DrawerHeaderSubtitleStyle = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Normal)
private val DrawerItemLabelStyle = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Medium)

/**
 * The stateless navigation drawer shell (010 §1.2, added to the 003 §4.3 component contract).
 * Platform-native mechanics underneath (`ModalNavigationDrawer`-class behavior, per 003 §4.3's
 * "re-skinned through tokens" rule) — the same category as `FindlyTheme`'s own Material3 mapping,
 * not one of the three documented "components only" exceptions (those are screens reaching past
 * the design system; this component *is* the design system's own implementation of the drawer).
 * Reads only [FindlyTheme] tokens; the caller supplies the fully pre-built, pre-gated [items]
 * (via [FindlyNavDrawerItems.build]) and the [familyName]/[callerDisplayName] header text — this
 * component never reaches into a ViewModel/network layer itself.
 */
@Composable
fun FindlyNavDrawer(
    drawerState: DrawerState,
    familyName: String,
    callerDisplayName: String,
    items: List<FindlyNavDrawerItem>,
    onItemSelected: (FindlyNavDrawerDestination) -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    ModalNavigationDrawer(
        drawerState = drawerState,
        modifier = modifier,
        drawerContent = {
            ModalDrawerSheet(drawerContainerColor = FindlyTheme.colors.surface) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(FindlyTheme.spacing.md),
                    verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs),
                ) {
                    Text(text = familyName, color = FindlyTheme.colors.onSurface, style = DrawerHeaderTitleStyle)
                    if (callerDisplayName.isNotBlank()) {
                        Text(text = callerDisplayName, color = FindlyTheme.colors.subtleText, style = DrawerHeaderSubtitleStyle)
                    }
                }

                Column {
                    items.forEach { item ->
                        FindlyNavDrawerRow(item = item, onClick = { onItemSelected(item.destination) })
                    }
                }
            }
        },
        content = content,
    )
}

@Composable
private fun FindlyNavDrawerRow(item: FindlyNavDrawerItem, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(if (item.selected) FindlyTheme.colors.surfaceVariant else FindlyTheme.colors.surface)
            .clickable(onClick = onClick)
            .padding(horizontal = FindlyTheme.spacing.md, vertical = FindlyTheme.spacing.sm),
        contentAlignment = Alignment.CenterStart,
    ) {
        Text(
            text = item.label,
            color = if (item.selected) FindlyTheme.colors.primary else FindlyTheme.colors.onSurface,
            style = DrawerItemLabelStyle,
        )
    }
}

/**
 * The 010 §1.2/§3.1 ☰ menu button — floating top chrome on the Family Map, the only screen that
 * renders it. 48dp circular, `surface` fill, `level2` shadow (§3.1's exact spec) — a themed text
 * glyph rather than a Material icon, mirroring [FindlyTopBar]'s own back-chevron rationale (no
 * material-icons dependency; components read only [FindlyTheme] tokens).
 */
@Composable
fun FindlyNavDrawerMenuButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val shape = CircleShape
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(48.dp)
            .shadow(elevation = FindlyTheme.elevation.level2, shape = shape)
            .clip(shape)
            .background(FindlyTheme.colors.surface)
            .clickable(onClick = onClick)
            .semantics { contentDescription = "Open menu" },
    ) {
        Text(text = "☰", color = FindlyTheme.colors.onSurface, style = TextStyle(fontSize = 20.sp))
    }
}

/** Convenience factory mirroring `rememberNavController()`'s call-site ergonomics — kept here so
 * every caller constructs the drawer's [DrawerState] the same way. */
@Composable
fun rememberFindlyNavDrawerState(initialValue: DrawerValue = DrawerValue.Closed): DrawerState = rememberDrawerState(initialValue)
