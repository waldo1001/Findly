package com.findly.android.queue.room

import androidx.room.Database
import androidx.room.RoomDatabase

/**
 * The app's single Room database (specs/009-device-runtime.md §2 — replaces the A1 in-memory
 * fix-queue placeholder, specs/003-android-client.md §10.4). `fixes` (A10) and `geofence_events`
 * (A11, §6.3) both live here rather than spinning up a second `RoomDatabase`, per the single-module
 * plan (specs/003 §3). Version bumped 1 -> 2 for the new `geofence_events` table;
 * `fallbackToDestructiveMigration()` (AppContainer) is the pragmatic choice pre-release (H1 still
 * pending, no real users/data to preserve across the schema change) rather than a hand-written
 * `Migration` for a table that never shipped with any rows in it.
 */
@Database(entities = [FixEntity::class, GeofenceEventEntity::class], version = 2, exportSchema = false)
abstract class FindlyDatabase : RoomDatabase() {
    abstract fun fixQueueDao(): FixQueueDao
    abstract fun geofenceEventDao(): GeofenceEventDao

    companion object {
        const val DATABASE_NAME = "findly.db"
    }
}
