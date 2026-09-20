package cn.blackbook.blackbook.recording

import org.json.JSONObject
import java.io.File

@androidx.annotation.Keep
object RecorderDaemon {
    @JvmStatic fun main(args:Array<String>) {
        if(android.os.Looper.myLooper()==null)android.os.Looper.prepareMainLooper()
        val dir=File(args[0]);val uid=args[1].toInt()
        val engine=try {RecorderEngine(dir,uid)} catch(e:RecordingBusyException) {
            println("录音进程已持有文件锁，本次重复启动退出")
            kotlin.system.exitProcess(73)
        }
        val generation=args.getOrNull(2) ?: "legacy"
        println("Recorder daemon started: pid=${android.os.Process.myPid()}, generation=$generation")
        var selftestUntil=0L
        while(true) {
            if(File(dir,"daemon-stop").exists()) {
                println("Recorder daemon stopping: saving audio and waiting for pending upload")
                engine.stop()
                engine.close()
                RecorderRuntime.keepAwake(false)
                engine.write(File(dir,"daemon-status.json"),JSONObject().put("daemon",false).put("recording",false).put("heartbeat",0).put("generation",generation).toString())
                println("Recorder daemon stopped")
                kotlin.system.exitProcess(0)
            }
            runCatching {
                val command=File(dir,"command.json")
                if(command.exists()) {
                    val c=JSONObject(command.readText());command.delete()
                    try {
                        when(c.getString("action")) {
                            "start" -> engine.start(c.optString("course_id","misc"))
                            "stop" -> engine.stop()
                            "pause" -> engine.pause(true)
                            "resume" -> engine.pause(false)
                            "retry" -> engine.retryDestination(c.optString("recording_id"))
                            "selftest" -> {
                                selftestUntil=System.currentTimeMillis()+30000
                                RecorderRuntime.keepAwake(true)
                                // Delay allows the user to lock the tablet before capture starts.
                                Thread {
                                    Thread.sleep(15000)
                                    val result=runCatching {engine.selfTest()}.getOrElse {JSONObject().put("passed",false).put("error",it.toString())}
                                    engine.write(File(dir,"selftest.json"),result.put("at",System.currentTimeMillis()).toString())
                                }.start()
                            }
                        }
                    } catch(t:Throwable) {engine.write(File(dir,"command-error.txt"),t.toString())}
                }
                val config=engine.config()
                RecorderRuntime.keepAwake((config.optBoolean("enabled") && config.optBoolean("auto_record")) || engine.status().optBoolean("recording") || System.currentTimeMillis()<selftestUntil)
                if(!config.optBoolean("enabled"))engine.stop(false)
                val verified=runCatching {JSONObject(File(dir,"selftest.json").readText()).optBoolean("passed")}.getOrDefault(false)
                if(config.optBoolean("enabled") && config.optBoolean("auto_record") && verified && !engine.status().optBoolean("recording")) {
                    val schedule=config.optJSONArray("occurrences")
                    val now=System.currentTimeMillis()
                    if(schedule!=null)for(i in 0 until schedule.length()) {
                        val item=schedule.getJSONObject(i)
                        val start=item.getLong("start_ms")-60000;val end=item.getLong("end_ms");val id=item.getString("id")
                        if(now in start until end && !File(dir,"skip-$id").exists()) {
                            engine.start(item.getString("course_id"),id,end);break
                        }
                    }
                }
                engine.write(File(dir,"daemon-status.json"),engine.status().put("daemon",true).put("pid",android.os.Process.myPid()).put("generation",generation).toString())
            }.onFailure {runCatching {engine.write(File(dir,"daemon-error.txt"),it.toString())}}
            Thread.sleep(1000)
        }
    }
}
