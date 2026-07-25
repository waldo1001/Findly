package com.findly.android.network

import com.findly.android.network.dto.FeaturesDto
import com.findly.android.network.dto.PlanFlagsDto
import com.findly.android.network.dto.PlanLimitsDto
import org.junit.Assert.assertEquals
import org.junit.Test

class FeaturesMapperTest {

    @Test
    fun `toDomain copies every field faithfully`() {
        val dto = FeaturesDto(
            subscriptionStatus = "free",
            limits = PlanLimitsDto(
                maxDevices = 10,
                maxGeofences = 20,
                historyDays = 90,
                minSyncIntervalMinutes = 5,
                locateRequestsPerDay = 100,
            ),
            flags = PlanFlagsDto(pushToLocate = true, geofencing = true, historyReplay = true),
        )

        val domain = dto.toDomain()

        assertEquals("free", domain.subscriptionStatus)
        assertEquals(10, domain.limits.maxDevices)
        assertEquals(20, domain.limits.maxGeofences)
        assertEquals(90, domain.limits.historyDays)
        assertEquals(5, domain.limits.minSyncIntervalMinutes)
        assertEquals(100, domain.limits.locateRequestsPerDay)
        assertEquals(true, domain.flags.pushToLocate)
        assertEquals(true, domain.flags.geofencing)
        assertEquals(true, domain.flags.historyReplay)
    }

    @Test
    fun `pre-groups fixtures without the 005 fields default to null limits and a false groups flag`() {
        val dto = FeaturesDto(
            subscriptionStatus = "free",
            limits = PlanLimitsDto(
                maxDevices = 10,
                maxGeofences = 20,
                historyDays = 90,
                minSyncIntervalMinutes = 5,
                locateRequestsPerDay = 100,
            ),
            flags = PlanFlagsDto(pushToLocate = true, geofencing = true, historyReplay = true),
        )

        val domain = dto.toDomain()

        assertEquals(null, domain.limits.maxActiveGroups)
        assertEquals(null, domain.limits.maxGroupMembers)
        assertEquals(null, domain.limits.maxGroupDurationDays)
        assertEquals(null, domain.limits.groupGraceDays)
        assertEquals(false, domain.flags.groups)
    }

    @Test
    fun `toDomain copies the specs 008 exportsPerDay limit`() {
        val dto = FeaturesDto(
            subscriptionStatus = "free",
            limits = PlanLimitsDto(
                maxDevices = 10,
                maxGeofences = 20,
                historyDays = 90,
                minSyncIntervalMinutes = 5,
                locateRequestsPerDay = 100,
                exportsPerDay = 3,
            ),
            flags = PlanFlagsDto(pushToLocate = true, geofencing = true, historyReplay = true),
        )

        val domain = dto.toDomain()

        assertEquals(3, domain.limits.exportsPerDay)
    }

    @Test
    fun `a fixture without exportsPerDay defaults it to null`() {
        val dto = FeaturesDto(
            subscriptionStatus = "free",
            limits = PlanLimitsDto(
                maxDevices = 10,
                maxGeofences = 20,
                historyDays = 90,
                minSyncIntervalMinutes = 5,
                locateRequestsPerDay = 100,
            ),
            flags = PlanFlagsDto(pushToLocate = true, geofencing = true, historyReplay = true),
        )

        assertEquals(null, dto.toDomain().limits.exportsPerDay)
    }

    @Test
    fun `toDomain copies the 001 §9 group-era limits and flag (specs 005)`() {
        val dto = FeaturesDto(
            subscriptionStatus = "free",
            limits = PlanLimitsDto(
                maxDevices = 10,
                maxGeofences = 20,
                historyDays = 90,
                minSyncIntervalMinutes = 5,
                locateRequestsPerDay = 100,
                maxActiveGroups = 5,
                maxGroupMembers = 50,
                maxGroupDurationDays = 30,
                groupGraceDays = 7,
            ),
            flags = PlanFlagsDto(pushToLocate = true, geofencing = true, historyReplay = true, groups = true),
        )

        val domain = dto.toDomain()

        assertEquals(5, domain.limits.maxActiveGroups)
        assertEquals(50, domain.limits.maxGroupMembers)
        assertEquals(30, domain.limits.maxGroupDurationDays)
        assertEquals(7, domain.limits.groupGraceDays)
        assertEquals(true, domain.flags.groups)
    }
}
