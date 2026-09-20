package cn.blackbook.blackbook.recording

import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject
import java.io.File

class RecorderBridge(private val activity:FlutterActivity,messenger:BinaryMessenger) {
    private val dir=File(activity.filesDir,"recording").also {it.mkdirs()}
    private val handler=Handler(Looper.getMainLooper())
    private var sink:EventChannel.EventSink?=null
    private var player:MediaPlayer?=null
    private var permissionResult:MethodChannel.Result?=null
    @Volatile private var installStage=""
    private val tick=object:Runnable {override fun run(){sink?.success(status().toString());handler.postDelayed(this,1000)}}
    init {
        EventChannel(messenger,"blackbook/recording/events").setStreamHandler(object:EventChannel.StreamHandler {
            override fun onListen(arguments:Any?,events:EventChannel.EventSink){sink=events;handler.post(tick)}
            override fun onCancel(arguments:Any?){sink=null;handler.removeCallbacks(tick)}
        })
        MethodChannel(messenger,"blackbook/recording").setMethodCallHandler {call,result ->
            when(call.method) {
                "permission" -> {
                    if(activity.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED)result.success(true)
                    else {permissionResult=result;activity.requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO,android.Manifest.permission.POST_NOTIFICATIONS),4812)}
                }
                "status" -> result.success(status().toString())
                "configure" -> runCatching {
                    val json=JSONObject(call.argument<String>("json") ?: "{}")
                    val file=File(dir,"config.json.new");file.writeText(json.toString());check(file.renameTo(File(dir,"config.json")))
                    if(!json.optBoolean("enabled")) {RecorderService.engine?.stop(false);command(JSONObject().put("action","stop"))}
                    result.success(null)
                }.onFailure {result.error("config",it.message,null)}
                "play" -> runCatching {
                    player?.release();player=MediaPlayer().apply {
                        setDataSource(activity,android.net.Uri.parse(call.argument<String>("url")),mapOf("X-API-Key" to (call.argument<String>("key") ?: "")))
                        setOnPreparedListener {it.seekTo(call.argument<Int>("position_ms") ?: 0);it.start();result.success(null)}
                        setOnErrorListener {_,what,extra -> result.error("playback","播放失败 $what/$extra",null);true}
                        prepareAsync()
                    }
                }.onFailure {result.error("playback",it.message,null)}
                "seek" -> {player?.seekTo(call.argument<Int>("position_ms") ?: 0);result.success(null)}
                "stopPlayback" -> {player?.release();player=null;result.success(null)}
                else -> Thread {
                    runCatching {
                        when(call.method) {
                            "localRecordings" -> LocalRecordings.list(dir).toString()
                            "sync", "retryUpload" -> {
                                val id=call.argument<String>("recording_id") ?: ""
                                if(id.isNotEmpty())check(runCatching {java.util.UUID.fromString(id)}.isSuccess) {"无效录音 ID"}
                                if(daemonAlive())command(JSONObject().put("action","retry").put("recording_id",id))
                                else if(RecorderService.engine!=null)RecorderService.engine?.retryDestination(id)
                                else activity.startForegroundService(Intent(activity,RecorderService::class.java).setAction("sync").putExtra("recording_id",id))
                                true
                            }
                            "root" -> root("id -u").trim()=="0"
                            "install" -> {try {installWithRecovery();true} finally {installStage=""}}
                            "stopDaemon" -> {try {stopDaemon();true} finally {installStage=""}}
                            "daemonLogs" -> root("if [ -f /data/adb/modules/blackbook_recorder/daemon.log ]; then tail -n 120 /data/adb/modules/blackbook_recorder/daemon.log; else echo '暂无守护日志'; fi")
                            "selftest" -> {check(daemonAlive()) {"请先安装并启动守护"};command(JSONObject().put("action","selftest"));true}
                            "start","stop","pause","resume","retry" -> {
                                if(daemonAlive())command(JSONObject().put("action",call.method).put("course_id",call.argument<String>("course_id") ?: "misc"))
                                else if(call.method=="retry") {
                                    if(RecorderService.engine!=null)RecorderService.engine?.retryDestination()
                                    else activity.startForegroundService(Intent(activity,RecorderService::class.java).setAction("sync"))
                                }
                                else {
                                    val intent=Intent(activity,RecorderService::class.java).setAction(call.method)
                                        .putExtra("course_id",call.argument<String>("course_id") ?: "misc")
                                    if(call.method=="start")activity.startForegroundService(intent)
                                    else RecorderService.engine?.let { when(call.method){"stop"->it.stop();"pause"->it.pause(true);"resume"->it.pause(false)} }
                                };true
                            }
                            else -> throw IllegalArgumentException("未知录音命令")
                        }
                    }.onSuccess {handler.post {result.success(it)}}.onFailure {handler.post {result.error("recording",it.message,null)}}
                }.start()
            }
        }
    }
    fun permissionResult(code:Int,grants:IntArray) {if(code==4812){permissionResult?.success(grants.firstOrNull()==PackageManager.PERMISSION_GRANTED);permissionResult=null}}
    private fun daemonAlive()=runCatching {val s=JSONObject(File(dir,"daemon-status.json").readText());s.optBoolean("daemon")&&System.currentTimeMillis()-s.getLong("heartbeat") in 0..5999}.getOrDefault(false)
    private fun status():JSONObject {
        val s=(if(daemonAlive())runCatching {JSONObject(File(dir,"daemon-status.json").readText())}.getOrNull() else null) ?: RecorderService.engine?.status() ?: JSONObject().put("recording",false)
        s.put("daemon",daemonAlive()).put("installed",File(dir,"module-installed").exists())
        s.put("install_stage",installStage)
        s.put("sync_running",daemonAlive() || RecorderService.engine!=null)
        s.put("selftest",runCatching {JSONObject(File(dir,"selftest.json").readText())}.getOrDefault(JSONObject()))
        s.put("player_position",runCatching {player?.currentPosition ?: 0}.getOrDefault(0))
        s.put("player_duration",runCatching {player?.duration ?: 0}.getOrDefault(0))
        for(name in listOf("command-error.txt","service-error.txt","daemon-error.txt")) {
            val f=File(dir,name);if(f.exists())s.put(name,f.readText().take(1000))
        }
        return s
    }
    private fun command(c:JSONObject) {val f=File(dir,"command.new");f.writeText(c.toString());check(f.renameTo(File(dir,"command.json")))}
    private fun quote(s:String)="'"+s.replace("'","'\\''")+"'"
    private fun root(command:String,timeout:Long=25):String {
        val p=ProcessBuilder("su","-c",command).redirectErrorStream(true).start()
        return RootCommandRunner.run(p,timeout*1000,installStage.ifEmpty {"root 请求"})
    }
    private val module="/data/adb/modules/blackbook_recorder"
    private fun enableModule() {
        root("""
test ! -f $module/remove || { echo '模块已标记删除，请在 root 管理器取消删除'; exit 1; }
if [ -x /data/adb/ksud ]; then
  /data/adb/ksud module enable blackbook_recorder || exit 1
elif [ -x /data/adb/ksu/bin/ksud ]; then
  /data/adb/ksu/bin/ksud module enable blackbook_recorder || exit 1
else
  rm -f $module/disable || exit 1
fi
test ! -f $module/disable || { echo '模块仍被禁用，请检查 root 管理器状态'; exit 1; }
""")
    }
    @Synchronized private fun installWithRecovery() {
        installStage="读取模块原启用状态"
        val previouslyEnabled=root("if [ -d $module ] && [ ! -f $module/disable ] && [ ! -f $module/remove ]; then echo enabled; fi").trim()=="enabled"
        try {
            install()
        } catch(t:Exception) {
            if(previouslyEnabled) {
                installStage="恢复模块原启用状态"
                try {
                    val stop=File(dir,"daemon-stop")
                    check(!stop.exists() || stop.delete()) {"无法清除临时停止标记"}
                    enableModule()
                } catch(restore:Exception) {
                    throw IllegalStateException("${t.message}\n恢复模块启用状态也失败：${restore.message}；请在 SukiSU/Magisk 中重新启用模块",t)
                }
            }
            throw t
        }
    }
    @Synchronized private fun stopDaemon() {
        installStage="获取 root 授权并禁用旧守护"
        val graceful=runCatching {JSONObject(File(dir,"daemon-status.json").readText()).has("generation")}.getOrDefault(false)
        root("if [ -d $module ]; then touch $module/disable; fi")
        File(dir,"daemon-stop").writeText("1")
        fun discover(): Map<String,List<Int>> {
            installStage="检查是否存在旧守护（最多 10 秒）"
            val rows=root(DaemonProcesses.discover(dir.path,module),10).lineSequence()
            val found=mutableMapOf<String,MutableList<Int>>()
            for(row in rows) {
                val parts=row.trim().split(' ')
                if(parts.size==2 && parts[0] in listOf("daemon","supervisor")) {
                    val pid=parts[1].toIntOrNull() ?: continue
                    if(pid>1)found.getOrPut(parts[0]) {mutableListOf()}.add(pid)
                }
            }
            return found
        }
        var processes=discover()
        val supervisors=processes["supervisor"].orEmpty()
        if(supervisors.isNotEmpty()) {
            installStage="停止已确认存在的守护启动器"
            root(DaemonProcesses.stop(dir.path,module,supervisors,"supervisor",false),10)
            // A supervisor could have launched a child just before it stopped.
            processes=discover()
        }
        val daemons=processes["daemon"].orEmpty()
        if(daemons.isNotEmpty()) {
            installStage="等待旧守护保存录音"
            command(JSONObject().put("action","stop"))
            if(!graceful) {
                val deadline=System.currentTimeMillis()+12000
                fun unfinished()=dir.listFiles()?.filter {it.isDirectory}?.any {
                    val manifest=File(it,"session.json")
                    manifest.exists() && !runCatching {JSONObject(manifest.readText()).optBoolean("finished")}.getOrDefault(false)
                } ?: false
                while(unfinished()&&System.currentTimeMillis()<deadline)Thread.sleep(250)
                check(!unfinished()) {"已发现旧守护，但录音尚未保存完成；未替换 APK"}
            }
            installStage="等待已确认的旧守护退出，PID：" + daemons.joinToString(", ")
            root(DaemonProcesses.stop(dir.path,module,daemons,"daemon",graceful),45)
        }
        // No matching process means no wait, regardless of stale heartbeat/manifests.
        File(dir,"daemon-status.json").delete()
        File(dir,"command.json").delete()
    }
    @Synchronized private fun install() {
        installStage="停止前台录音服务"
        RecorderService.engine?.stop()
        activity.stopService(Intent(activity,RecorderService::class.java))
        val until=System.currentTimeMillis()+30000
        while(RecorderService.engine!=null&&System.currentTimeMillis()<until)Thread.sleep(100)
        check(RecorderService.engine==null) {"前台录音服务尚未退出，请稍后重试"}
        stopDaemon()
        val generation=java.util.UUID.randomUUID().toString()
        val script=File(dir,"service.sh")
        script.writeText("""#!/system/bin/sh
MODDIR=${'$'}{0%/*}
if [ "${'$'}1" != '--now' ]; then
  while [ "${'$'}(getprop sys.boot_completed)" != "1" ]; do sleep 5; done
fi
while [ ! -d ${quote(dir.path)} ]; do sleep 5; done
# RecorderEngine owns capture.lock for its entire lifetime.
# Exit 73 means another recording process owns it: retire this duplicate launcher.
while [ ! -f "${'$'}MODDIR/disable" ] && [ ! -f "${'$'}MODDIR/remove" ]; do
  CLASSPATH="${'$'}MODDIR/recorder.apk" app_process / cn.blackbook.blackbook.recording.RecorderDaemon ${quote(dir.path)} ${activity.applicationInfo.uid} '$generation' >>"${'$'}MODDIR/daemon.log" 2>&1
  result=${'$'}?
  if [ "${'$'}result" = 73 ]; then exit 0; fi
  sleep 5
done
""")
        val prop=File(dir,"module.prop").apply {writeText("id=blackbook_recorder\nname=Blackbook Classroom Recorder\nversion=1.0\nversionCode=1\nauthor=Blackbook\ndescription=Local classroom recording daemon\n")}
        installStage="复制新版守护 APK"
        root("mkdir -p $module && cp ${quote(activity.applicationInfo.sourceDir)} $module/recorder.apk.new && mv $module/recorder.apk.new $module/recorder.apk && cp ${quote(script.path)} $module/service.sh && cp ${quote(prop.path)} $module/module.prop && chmod 700 $module/service.sh")
        File(dir,"daemon-stop").delete()
        File(dir,"selftest.json").delete()
        installStage="启用模块（SukiSU / Magisk）"
        enableModule()
        installStage="启动新版守护"
        root("""
test ! -f $module/remove || { echo '模块已标记删除，请在 root 管理器取消删除'; exit 1; }
command -v setsid >/dev/null 2>&1 || { echo '系统缺少 setsid，无法独立启动守护'; exit 1; }
test ! -f $module/disable || { echo '模块已被禁用，未启动守护'; exit 1; }
echo '--- App 请求启动守护 ---' >>$module/daemon.log
nohup setsid sh $module/service.sh --now >>$module/daemon.log 2>&1 < /dev/null &
""")
        val deadline=System.currentTimeMillis()+20000
        installStage="等待新版守护心跳（最多 20 秒）"
        while(System.currentTimeMillis()<deadline) {
            val current=runCatching {JSONObject(File(dir,"daemon-status.json").readText())}.getOrNull()
            if(daemonAlive()&&current?.optString("generation")==generation) {
                File(dir,"module-installed").writeText("1")
                return
            }
            Thread.sleep(250)
        }
        installStage="读取守护启动诊断"
        val diagnostic=runCatching {root("tail -n 15 $module/daemon.log",5)}.getOrDefault("无法读取启动日志")
        error("新守护未产生心跳，录音文件保留。启动日志：\n${diagnostic.takeLast(2000)}")
    }
    fun dispose(){handler.removeCallbacks(tick);player?.release();sink=null}
}
