package cn.blackbook.blackbook.recording

import java.io.Closeable
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.OverlappingFileLockException

internal class RecordingBusyException : IllegalStateException("另一个录音服务已在运行")

/** Owned by the recording process itself; no inherited shell descriptor required. */
internal class RecordingProcessLock(file: File) : Closeable {
    private val channel = RandomAccessFile(file, "rw").channel
    private val lock = try {
        channel.tryLock() ?: throw RecordingBusyException()
    } catch (e: Exception) {
        channel.close()
        if (e is OverlappingFileLockException) throw RecordingBusyException()
        throw e
    }

    override fun close() {
        try { if (lock.isValid) lock.release() } finally { channel.close() }
    }
}
