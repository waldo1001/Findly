package com.findly.android.fakes

import com.findly.android.queue.worker.LastCaptureDateStore
import java.time.LocalDate

class InMemoryLastCaptureDateStore(initial: LocalDate? = null) : LastCaptureDateStore {
    private var stored: LocalDate? = initial

    override suspend fun lastCaptureDate(): LocalDate? = stored

    override suspend fun recordCaptureDate(date: LocalDate) {
        stored = date
    }
}
