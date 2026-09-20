package cn.blackbook.blackbook.recording

import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Drain output without allowing pipe-close exceptions to escape a child thread. */
internal object RootCommandRunner {
    fun run(process: Process, timeoutMillis: Long, stage: String): String {
        val output = StringBuffer()
        val readFailure = AtomicReference<Exception?>()
        val reader = Thread({
            try {
                process.inputStream.reader().use { stream ->
                    val buffer = CharArray(2048)
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        synchronized(output) {
                            output.append(buffer, 0, count)
                            if (output.length > 16384) output.delete(0, output.length - 16384)
                        }
                    }
                }
            } catch (e: Exception) {
                readFailure.set(e)
            }
        }, "recording-root-output").apply { isDaemon = true; start() }
        try {
            if (!process.waitFor(timeoutMillis, TimeUnit.MILLISECONDS)) {
                throw IllegalStateException("$stage 超时（${timeoutMillis / 1000} 秒）；请检查 Magisk 授权并查看守护日志")
            }
            reader.join(1000)
            val text = output.toString()
            check(process.exitValue() == 0) {
                "$stage 失败（退出码 ${process.exitValue()}）：${text.takeLast(800)}"
            }
            check(!reader.isAlive) { "$stage：命令已结束，但输出管道未关闭" }
            readFailure.get()?.let { throw IllegalStateException("$stage：读取 root 输出失败", it) }
            return text
        } finally {
            // Android can interrupt a blocked pipe read when this process is destroyed.
            // The reader handles that exception locally; timeout remains the caller's error.
            runCatching { process.destroyForcibly() }
            runCatching { process.inputStream.close() }
            runCatching { process.errorStream.close() }
            runCatching { process.outputStream.close() }
            runCatching { reader.join(1000) }
        }
    }
}
