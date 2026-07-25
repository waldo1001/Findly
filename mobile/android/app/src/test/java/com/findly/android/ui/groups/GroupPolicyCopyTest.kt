package com.findly.android.ui.groups

import org.junit.Assert.assertEquals
import org.junit.Test

/** [GroupPolicyCopy] surfaces the exact plain-language promise specs/005-temporary-groups.md
 * §2.1 requires clients show at group creation ("clients MUST show this at creation"). */
class GroupPolicyCopyTest {

    @Test
    fun `delete policy copy matches 005 section 2_1 verbatim`() {
        assertEquals(
            "When the group ends, everything about it disappears.",
            GroupPolicyCopy.forPolicy("delete"),
        )
    }

    @Test
    fun `grace policy copy matches 005 section 2_1 verbatim`() {
        assertEquals(
            "When the group ends it goes read-only for a few days so the owner can revive it; then everything disappears.",
            GroupPolicyCopy.forPolicy("grace"),
        )
    }

    @Test
    fun `archive policy copy matches 005 section 2_1 verbatim`() {
        assertEquals(
            "When the group ends, everyone's locations are deleted; the member list stays as a keepsake.",
            GroupPolicyCopy.forPolicy("archive"),
        )
    }

    @Test
    fun `an unrecognized policy never crashes — falls back to an empty string`() {
        assertEquals("", GroupPolicyCopy.forPolicy("not-a-real-policy"))
    }

    @Test
    fun `all three policies are exposed for a picker`() {
        assertEquals(listOf("delete", "grace", "archive"), GroupPolicyCopy.ALL_POLICIES)
    }
}
