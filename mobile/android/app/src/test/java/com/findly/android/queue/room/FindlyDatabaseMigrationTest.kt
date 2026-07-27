package com.findly.android.queue.room

import android.content.Context
import android.content.ContextWrapper
import androidx.room.Room
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import java.io.File
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Verifies [MIGRATION_1_2] against a **real** SQLite engine — Room's "bundled driver"
 * (`androidx.sqlite:sqlite-bundled`) runs a genuine file-backed SQLite database from a plain JUnit
 * test, no Robolectric/instrumentation (specs/003-android-client.md §14's "no Robolectric"
 * convention stays intact — this is a JVM-native SQLite engine, not an Android-framework shadow).
 * [fakeContext] is a bare `ContextWrapper` — `Room.databaseBuilder` still requires a `Context`
 * parameter even with a non-framework `driver` set, and unconditionally resolves the database
 * file through `Context.getDatabasePath(name)` (`RoomConnectionManager.resolveFileName`) even for
 * an already-**absolute** path. This project's existing `testOptions.unitTests.isReturnDefaultValues
 * = true` (app/build.gradle.kts) makes every other unimplemented Android-framework method return a
 * harmless default instead of throwing, but `getDatabasePath`'s stub default is `null`, which Room
 * immediately dereferences — so this one method needs a real override (`File(name)`, since [dbFile]
 * is already absolute) rather than relying on the stub.
 *
 * Code-review fix (post-A11 review): `fallbackToDestructiveMigration` would have wiped the
 * pre-existing `fixes` table (A10's durable queue) on every 1 -> 2 upgrade, not just the new
 * `geofence_events` table. This test proves the real migration does the opposite: a `fixes` row
 * written under the v1 schema survives the upgrade to v2 untouched, and the new `geofence_events`
 * table exists and is usable afterward.
 */
class FindlyDatabaseMigrationTest {

    private val dbFile = File.createTempFile("findly-migration-test", ".db")
    private val fakeContext: Context = object : ContextWrapper(null) {
        override fun getDatabasePath(name: String): File = File(name)
    }

    @After
    fun tearDown() {
        dbFile.delete()
        File("${dbFile.path}-wal").delete()
        File("${dbFile.path}-shm").delete()
    }

    @Test
    fun `a v1 fixes row survives the 1 to 2 migration untouched`() = runTest {
        // Build at v1 (only the fixes table, with the exact column/index shape FixEntity's own
        // Room codegen would have created) and insert one row directly via SQL - this doesn't go
        // through FindlyDatabase's current (v2) entity set at all.
        BundledSQLiteDriver().open(dbFile.path).use { connection ->
            connection.execSQL(
                """
                CREATE TABLE `fixes` (
                    `seq` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    `fixId` TEXT NOT NULL,
                    `recordedAt` TEXT NOT NULL,
                    `lat` REAL NOT NULL,
                    `lon` REAL NOT NULL,
                    `accuracyM` REAL NOT NULL,
                    `altitudeM` REAL,
                    `speedMps` REAL,
                    `bearingDeg` REAL,
                    `batteryPct` INTEGER NOT NULL,
                    `source` TEXT NOT NULL,
                    `batchId` TEXT
                )
                """.trimIndent(),
            )
            connection.execSQL(
                "CREATE UNIQUE INDEX `index_fixes_fixId` ON `fixes` (`fixId`)",
            )
            connection.execSQL(
                "CREATE INDEX `index_fixes_batchId` ON `fixes` (`batchId`)",
            )
            connection.execSQL(
                "INSERT INTO fixes (fixId, recordedAt, lat, lon, accuracyM, batteryPct, source, batchId) " +
                    "VALUES ('fix-1', '2026-07-27T09:00:00Z', 51.05, 3.71, 10.0, 80, 'periodic', NULL)",
            )
            // So Room recognizes this file as "a Room database currently at version 1" when
            // re-opened through the real builder below.
            connection.execSQL("PRAGMA user_version = 1")
        }

        // Re-open through the real FindlyDatabase builder (v2) with only MIGRATION_1_2 supplied -
        // no fallbackToDestructiveMigration - so a missing/wrong migration would fail this test
        // with Room's own "no migration found"/schema-validation exception instead of silently
        // wiping data.
        val database = Room.databaseBuilder(fakeContext, FindlyDatabase::class.java, dbFile.path)
            .setDriver(BundledSQLiteDriver())
            .addMigrations(MIGRATION_1_2)
            .build()

        val survivingFixes = database.fixQueueDao().pendingFixesOrdered()
        assertEquals(1, survivingFixes.size)
        assertEquals("fix-1", survivingFixes.single().fixId)

        // The new table exists and is genuinely usable post-migration, not just present.
        val geofenceEventDao = database.geofenceEventDao()
        geofenceEventDao.insert(
            GeofenceEventEntity(
                eventId = "evt-1",
                geofenceId = "gf_home",
                transition = "enter",
                recordedAt = "2026-07-27T09:00:00Z",
                batchId = null,
            ),
        )
        assertEquals(1, geofenceEventDao.totalCount())

        database.close()
    }

    @Test
    fun `MIGRATION_1_2 is registered for exactly the 1 to 2 upgrade`() {
        assertEquals(1, MIGRATION_1_2.startVersion)
        assertEquals(2, MIGRATION_1_2.endVersion)
    }
}
