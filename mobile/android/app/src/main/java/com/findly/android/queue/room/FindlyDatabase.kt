package com.findly.android.queue.room

import androidx.room.Database
import androidx.room.RoomDatabase

/**
 * The app's single Room database (specs/009-device-runtime.md §2 — replaces the A1 in-memory
 * fix-queue placeholder, specs/003-android-client.md §10.4). One table today (`fixes`); a future
 * table lives here too rather than spinning up a second `RoomDatabase`, per the single-module
 * plan (specs/003 §3).
 */
@Database(entities = [FixEntity::class], version = 1, exportSchema = false)
abstract class FindlyDatabase : RoomDatabase() {
    abstract fun fixQueueDao(): FixQueueDao

    companion object {
        const val DATABASE_NAME = "findly.db"
    }
}
