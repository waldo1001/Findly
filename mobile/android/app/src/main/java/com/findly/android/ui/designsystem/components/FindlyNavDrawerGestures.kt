package com.findly.android.ui.designsystem.components

/**
 * Pure policy behind `ModalNavigationDrawer(gesturesEnabled = …)` (010 §1.2, amended 2026-10-12):
 * a closed drawer must never take a drag, so the full-bleed map can pan in every direction.
 * No Compose import — unit-testable with plain JUnit.
 */
object FindlyNavDrawerGestures {
    fun enabled(isOpen: Boolean): Boolean = isOpen
}
