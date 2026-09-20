package cn.blackbook.blackbook.recording

import org.junit.Assert.assertThrows
import org.junit.Test
import java.nio.file.Files

class RecordingProcessLockTest {
    @Test fun duplicateIsRejectedAndReleaseAllowsRestart() {
        val file=Files.createTempFile("recording-lock", ".lock").toFile()
        try {
            RecordingProcessLock(file).use {
                repeat(3) {
                    assertThrows(RecordingBusyException::class.java) {RecordingProcessLock(file)}
                }
            }
            // A failed duplicate must not leak a descriptor/lock and block the next start.
            RecordingProcessLock(file).use { }
        } finally {file.delete()}
    }
}
