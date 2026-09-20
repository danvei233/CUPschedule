package cn.blackbook.blackbook.recording

import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit

class DaemonProcessesTest {
    private fun shell(script: String, files: Map<Int, List<String>> = emptyMap()): String {
        val bash = if (System.getProperty("os.name", "").startsWith("Windows"))
            File("C:/Program Files/Git/bin/bash.exe") else File("/bin/bash")
        assumeTrue("Shell integration test requires bash", bash.exists())
        val directory = Files.createTempDirectory("recorder-process-test").toFile()
        try {
            File(directory,"proc").mkdirs()
            for ((pid,args) in files) {
                File(directory,"proc/$pid").mkdirs()
                File(directory,"proc/$pid/cmdline").writeBytes((args.joinToString("\u0000")+"\u0000").toByteArray())
            }
            File(directory,"test.sh").writeText(script)
            val p = ProcessBuilder(bash.path,"test.sh").directory(directory).redirectErrorStream(true).start()
            try {
                assertTrue("Process discovery must finish without waiting for absent daemons",p.waitFor(5,TimeUnit.SECONDS))
                val output=p.inputStream.bufferedReader().readText()
                assertEquals(output,0,p.exitValue())
                return output.trim()
            } finally {p.destroyForcibly()}
        } finally {directory.deleteRecursively()}
    }

    @Test fun emptyProcessListReturnsImmediately() {
        assertEquals("",shell(DaemonProcesses.discover("/app/recording","/module","proc")))
        assertEquals("",shell(DaemonProcesses.stop("/app/recording","/module",emptyList(),"daemon",true)))
    }

    @Test fun matchesExactArgumentsAndExcludesOwnSuCommand() {
        val daemon="cn.blackbook.blackbook.recording.RecorderDaemon"
        val processes=(10..1510).associateWith {listOf("unrelated-process")}.toMutableMap()
        processes[2000]=listOf("app_process","/",daemon,"/app/recording","123")
        processes[2001]=listOf("sh","/module/service.sh","--now")
        processes[2002]=listOf("su","-c","$daemon /app/recording /module/service.sh")
        processes[2003]=listOf("app_process","/",daemon,"/other-app/recording")
        assertEquals(setOf("daemon 2000","supervisor 2001"),shell(DaemonProcesses.discover("/app/recording","/module","proc"),processes).lines().toSet())
    }
}
