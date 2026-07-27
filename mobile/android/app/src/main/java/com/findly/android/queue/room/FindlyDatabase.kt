package com.findly.android.queue.room

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.execSQL

/**
 * The app's single Room database (specs/009-device-runtime.md §2 — replaces the A1 in-memory
 * fix-queue placeholder, specs/003-android-client.md §10.4). `fixes` (A10) and `geofence_events`
 * (A11, §6.3) both live here rather than spinning up a second `RoomDatabase`, per the single-module
 * plan (specs/003 §3). Version bumped 1 -> 2 for the new `geofence_events` table, via
 * [MIGRATION_1_2] — **not** `fallbackToDestructiveMigration`, which would have wiped the
 * pre-existing `fixes` table (A10's durable queue) on every upgrade, not just the new empty
 * table (code-review finding, post-A11 review).
 */
@Database(entities = [FixEntity::class, GeofenceEventEntity::class], version = 2, exportSchema = false)
abstract class FindlyDatabase : RoomDatabase() {
    abstract fun fixQueueDao(): FixQueueDao
    abstract fun geofenceEventDao(): GeofenceEventDao

    companion object {
        const val DATABASE_NAME = "findly.db"
    }
}

/**
 * 1 -> 2: adds the `geofence_events` table only ([GeofenceEventEntity]'s exact column/index
 * definitions) — the pre-existing `fixes` table (and any other v1 state) is left completely
 * untouched. Verified against a real SQLite engine in `FindlyDatabaseMigrationTest`
 * (`androidx.sqlite:sqlite-bundled`'s JVM driver — no Robolectric/instrumentation needed,
 * specs/003-android-client.md §14). Index names match Room's own generated
 * `index_<table>_<column(s)>` convention exactly, so Room's runtime schema validation (which
 * Room performs on every open, independent of `exportSchema`) accepts the migrated result as
 * identical to what [GeofenceEventEntity]'s annotations declare.
 */
val MIGRATION_1_2: Migration = object : Migration(startVersion = 1, endVersion = 2) {
    override fun migrate(connection: SQLiteConnection) {
        connection.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `geofence_events` (
                `seq` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `eventId` TEXT NOT NULL,
                `geofenceId` TEXT NOT NULL,
                `transition` TEXT NOT NULL,
                `recordedAt` TEXT NOT NULL,
                `batchId` TEXT
            )
            """.trimIndent(),
        )
        connection.execSQL(
            "CREATE UNIQUE INDEX IF NOT EXISTS `index_geofence_events_eventId` ON `geofence_events` (`eventId`)",
        )
        connection.execSQL(
            "CREATE INDEX IF NOT EXISTS `index_geofence_events_batchId` ON `geofence_events` (`batchId`)",
        )
    }
}
