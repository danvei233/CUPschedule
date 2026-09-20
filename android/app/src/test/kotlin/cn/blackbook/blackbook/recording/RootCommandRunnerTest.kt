package cn.blackbook.blackbook.recording

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.InterruptedIOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class RootCommandRunnerTest {
    private class FakeProcess(val source: InputStream, val completes: Boolean = true, val code: Int = 0) : Process() {
        var destroyed = false
        override fun getInputStream() = source
        override fun getErrorStream() = ByteArrayInputStream(byteArrayOf())
        override fun getOutputStream() = ByteArrayOutputStream()
        override fun waitFor() = code
        override fun waitFor(timeout: Long, unit: TimeUnit) = completes
        override fun exitValue() = code
        override fun destroy() { destroyed = true; source.close() }
        override fun destroyForcibly(): Process { destroy(); return this }
    }

    @Test fun timeoutWithInterruptedReaderDoesNotEscapeThread() {
        val entered = CountDownLatch(1)
        val closed = CountDownLatch(1)
        val source = object : InputStream() {
            override fun read(): Int {
                entered.countDown()
                closed.await(5, TimeUnit.SECONDS)
                throw InterruptedIOException("read interrupted by close() on another thread")
            }
            override fun close() { closed.countDown() }
        }
        val uncaught = AtomicReference<Throwable?>()
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { _, e -> uncaught.set(e) }
        try {
            val process = FakeProcess(source, completes = false)
            val error = assertThrows(IllegalStateException::class.java) {
                RootCommandRunner.run(process, 10, "等待旧守护退出")
            }
            assertTrue(error.message!!.contains("等待旧守护退出 超时"))
            assertTrue(process.destroyed)
            assertNull(uncaught.get())
        } finally {
            Thread.setDefaultUncaughtExceptionHandler(previous)
        }
    }

    @Test fun readerFailureIsReturnedToCaller() {
        val source = object : InputStream() {
            override fun read(): Int = throw InterruptedIOException("closed")
        }
        val error = assertThrows(IllegalStateException::class.java) {
            RootCommandRunner.run(FakeProcess(source), 1000, "复制 APK")
        }
        assertTrue(error.cause is InterruptedIOException)
    }

    @Test fun successfulOutputAndNonzeroExit() {
        assertEquals("0\n", RootCommandRunner.run(FakeProcess(ByteArrayInputStream("0\n".toByteArray())), 1000, "授权"))
        val error = assertThrows(IllegalStateException::class.java) {
            RootCommandRunner.run(FakeProcess(ByteArrayInputStream("permission denied".toByteArray()), code = 1), 1000, "授权")
        }
        assertTrue(error.message!!.contains("permission denied"))
    }
}
