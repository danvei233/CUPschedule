package cn.blackbook.blackbook.recording

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.StatFs
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** Shared by the foreground service and the Magisk app_process entry point. */
class RecorderEngine(private val dir: File, private val owner: Int? = null,
    private val transport:((String,String,String,String,JSONObject)->JSONObject)?=null) {
    private val alive = AtomicBoolean(true)
    @Volatile private var session: JSONObject? = null
    @Volatile private var paused = false
    @Volatile private var level = 0.0
    @Volatile private var error = ""
    @Volatile private var uploadError = ""
    private val testing=AtomicBoolean(false)
    private var capture: Thread? = null
    private var uploader:Thread?=null
    private val retryIds=java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private val uploadSignal=Object()
    private val processLock=RecordingProcessLock(File(dir.also {it.mkdirs()},"capture.lock"))
    init {
        dir.mkdirs()
        own(File(dir,"capture.lock"))
        // Recover interrupted sessions as complete files, explicitly marking the interruption.
        dir.listFiles()?.filter { it.isDirectory }?.forEach { folder ->
            val f = File(folder, "session.json")
            runCatching { val s = JSONObject(f.readText()); if (!s.optBoolean("finished")) {
                s.put("finished", true).put("interrupted", true)
                val chunks=folder.listFiles()?.filter { it.extension=="pcm" } ?: emptyList()
                s.put("total_chunks",chunks.size).put("samples",chunks.sumOf {it.length()/2})
                write(f, s.toString())
            } }
        }
        uploader=Thread({ while(alive.get()) { runCatching { upload() }.onFailure { uploadError = it.message ?: "上传失败" }; synchronized(uploadSignal) {if(alive.get())uploadSignal.wait(2500)} } }, "recording-upload").also {it.start()}
    }
    fun config(): JSONObject = runCatching { JSONObject(File(dir,"config.json").readText()) }.getOrDefault(JSONObject())
    @Synchronized fun start(course: String, occurrence: String = "", end: Long = 0) {
        check(session == null) { "已有录音会话" }
        check(!testing.get()) { "麦克风自检正在进行" }
        val id = UUID.randomUUID().toString()
        val folder = File(dir,id); folder.mkdirs(); own(folder)
        val s = JSONObject().put("id",id).put("course_id",course).put("occurrence",occurrence)
            .put("end_ms",end).put("started_at",java.time.Instant.now().toString())
            .put("title",if(occurrence.isEmpty()) "手动录音" else "课堂录音")
            .put("finished",false).put("total_chunks",0).put("samples",0).put("acked",-1).put("gaps",JSONArray())
        // Snapshot destination so changing settings cannot send old sessions to another server.
        s.put("base_url",config().optString("base_url")).put("api_key",config().optString("api_key"))
        save(s); session=s; paused=false; error=""
        capture=Thread({ record(s,folder) },"recording-capture").also { it.start() }
    }
    fun pause(value: Boolean) {
        val s=session ?: return
        synchronized(s) {
            if(value&&!paused)s.put("pause_at",System.currentTimeMillis())
            if(!value&&paused){s.getJSONArray("gaps").put(JSONObject().put("from_ms",s.optLong("pause_at")).put("to_ms",System.currentTimeMillis()).put("reason","paused"));save(s)}
            paused=value
        }
    }
    fun stop(manual: Boolean = true) {
        val s=session ?: return
        if(paused)pause(false)
        if(manual && s.optString("occurrence").isNotEmpty()) write(File(dir,"skip-${s.getString("occurrence")}"),"1")
        session=null; capture?.join(3000)
    }
    fun close() {
        alive.set(false);synchronized(uploadSignal) {uploadSignal.notifyAll()};stop(false)
        capture?.join()
        uploader?.join()
        processLock.close()
    }
    fun status(): JSONObject {
        val s=session
        return JSONObject().put("recording",s != null).put("id",s?.optString("id") ?: "")
            .put("paused",paused).put("level",level).put("error",error).put("upload_error",uploadError)
            .put("chunks",s?.optInt("total_chunks") ?: 0).put("acked",s?.optInt("acked",-1) ?: -1)
            .put("duration_seconds",(s?.optLong("samples") ?: 0)/16000.0)
            .put("course_id",s?.optString("course_id") ?: "").put("heartbeat",System.currentTimeMillis())
            .put("started_at",s?.optString("started_at") ?: "")
    }
    private fun newRecorder(): AudioRecord {
        val minimum=AudioRecord.getMinBufferSize(16000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT)
        check(minimum>0) { "设备不支持 16kHz PCM 麦克风" }
        val builder=AudioRecord.Builder().setAudioSource(MediaRecorder.AudioSource.MIC)
            .setAudioFormat(AudioFormat.Builder().setSampleRate(16000).setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()).setBufferSizeInBytes(maxOf(minimum*2,32000))
        // On app_process there is no Activity context. Use the framework system context when available;
        // OEM attribution/SELinux rejection is surfaced by the mandatory background self-test.
        if(owner != null) runCatching {
            builder.javaClass.getMethod("setContext",android.content.Context::class.java).invoke(builder,RecorderRuntime.context)
        }
        return builder.build().also { check(it.state==AudioRecord.STATE_INITIALIZED) { "麦克风初始化失败" } }
    }
    fun selfTest(): JSONObject {
        check(session==null) { "请先结束录音" }
        check(testing.compareAndSet(false,true)) {"自检正在进行"}
        return runCatching {
            if(owner!=null)check(!RecorderRuntime.context.getSystemService(android.os.PowerManager::class.java).isInteractive) {"请在点击自检后锁屏，再重试"}
            val r=newRecorder(); try {
                r.startRecording(); val b=ShortArray(16000); var read=0; var peak=0
                repeat(3) { val n=r.read(b,0,b.size); check(n>0) { "麦克风读取失败 $n" };read+=n; for(i in 0 until n) peak=maxOf(peak,kotlin.math.abs(b[i].toInt())) }
                check(peak>0) { "收到全零音频：检查后台麦克风权限或系统静音" }
                JSONObject().put("passed",true).put("samples",read).put("peak",peak)
            } finally { runCatching { r.stop() };r.release() }
        }.getOrElse { JSONObject().put("passed",false).put("error",it.toString()) }.also {testing.set(false)}
    }
    private fun record(s:JSONObject, folder:File) {
        var recorder:AudioRecord?=null
        try {
            recorder=newRecorder();recorder.startRecording()
            val buffer=ByteArray(32000);var seq=0
            while(session===s) {
                if(s.optLong("end_ms")>0 && System.currentTimeMillis()>=s.optLong("end_ms")) {session=null;break}
                check(StatFs(dir.path).availableBytes>32L*1024*1024) { "空间不足，录音已保存" }
                val n=recorder.read(buffer,0,buffer.size);check(n>0) { "麦克风中断 $n" }
                if(paused) continue
                var peak=0;for(i in 0 until n-1 step 2) {val v=((buffer[i].toInt() and 255) or (buffer[i+1].toInt() shl 8)).toShort();peak=maxOf(peak,kotlin.math.abs(v.toInt()))};level=peak/32768.0
                val f=File(folder,"$seq.pcm");val tmp=File(folder,"$seq.tmp")
                tmp.outputStream().use { it.write(buffer,0,n);it.fd.sync() };check(tmp.renameTo(f));own(f)
                synchronized(s) {seq++;s.put("total_chunks",seq).put("samples",s.optLong("samples")+n/2);save(s)}
            }
        } catch(t:Throwable) {error=t.message ?: t.toString();s.put("capture_error",error).put("interrupted",true)}
        finally {
            runCatching { recorder?.stop() };recorder?.release()
            synchronized(s) {s.put("finished",true);save(s)}
            if(session===s)session=null
        }
    }
    private fun transferState(folder:File,state:String,message:String="") {
        write(File(folder,"upload-state.json"),JSONObject().put("state",state).put("error",message).put("updated_at",System.currentTimeMillis()).toString())
    }
    private fun upload() {
        val folders=dir.listFiles()?.filter {it.isDirectory}?.sortedByDescending {if(retryIds.contains(it.name))2 else if(session?.optString("id")==it.name)1 else 0} ?: return
        for(folder in folders) {
            if(!alive.get())return
            val file=File(folder,"session.json");if(!file.exists())continue
            try {
                val s=session?.takeIf {it.optString("id")==folder.name} ?: JSONObject(file.readText())
                if(s.optBoolean("uploaded")) {
                    if(System.currentTimeMillis()-s.optLong("uploaded_at")>7L*86400000)folder.deleteRecursively()
                    continue
                }
                val cfg=config()
                val destination=s.optString("base_url").trimEnd('/')
                val configured=cfg.optString("base_url").trimEnd('/')
                if(destination.isNotEmpty() && destination!=configured) {
                    transferState(folder,"different_server","该录音属于其他服务器，请切回录制时的后端地址再上传");continue
                }
                synchronized(s) {
                    if(cfg.optString("api_key").isNotEmpty() && configured.isNotEmpty()) {
                        s.put("base_url",configured).put("api_key",cfg.optString("api_key"));save(s)
                    }
                }
                val base=s.optString("base_url");val key=s.optString("api_key")
                if(base.isEmpty() || key.isEmpty()) {
                    transferState(folder,"waiting_config","请先配置后端地址和 API key");continue
                }
                val id=s.getString("id")
                if(s.optInt("total_chunks")==0) {
                    transferState(folder,if(s.optBoolean("finished"))"failed" else "local",if(s.optBoolean("finished"))"没有采集到有效音频，请查看麦克风错误" else "")
                    continue
                }
                retryIds.remove(id)
                transferState(folder,"uploading")
                val metadata=JSONObject().put("id",id).put("course_id",s.getString("course_id")).put("title",s.optString("title")).put("started_at",s.optString("started_at"))
                request(base,key,"POST","/recordings",metadata)
                val chunks=request(base,key,"GET","/recordings/$id/chunks",JSONObject()).optJSONArray("chunks") ?: JSONArray()
                val present=mutableSetOf<Int>();for(i in 0 until chunks.length())present.add(chunks.getJSONObject(i).getInt("seq"))
                var ack=-1;while(present.contains(ack+1))ack++
                synchronized(s) {s.put("acked",ack);save(s)}
                // Bounded batches prevent one long backlog starving other recordings.
                var sent=0
                while(ack+1<s.optInt("total_chunks") && sent<8) {
                    if(!alive.get())return
                    val seq=ack+1;val bytes=File(folder,"$seq.pcm").readBytes()
                    val hash=MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {"%02x".format(it)}
                    request(base,key,"POST","/recordings/$id/chunks",JSONObject().put("seq",seq).put("sha256",hash).put("data",java.util.Base64.getEncoder().encodeToString(bytes)))
                    synchronized(s) {ack=seq;s.put("acked",ack);save(s)}
                    sent++
                }
                if(s.optBoolean("finished") && ack+1==s.optInt("total_chunks")) {
                    transferState(folder,"verifying")
                    request(base,key,"PATCH","/recordings/$id",JSONObject().put("interrupted",s.optBoolean("interrupted")).put("capture_error",s.optString("capture_error")).put("gaps",s.optJSONArray("gaps")?.toString() ?: "[]"))
                    request(base,key,"POST","/recordings/$id/complete",JSONObject().put("total_chunks",s.getInt("total_chunks")))
                    synchronized(s) {s.put("uploaded",true).put("uploaded_at",System.currentTimeMillis());save(s)}
                    transferState(folder,"uploaded")
                }
                uploadError=""
            } catch(t:Exception) {
                uploadError=t.message ?: "上传失败，稍后自动重试"
                val network=t is UploadNetworkException
                runCatching {transferState(folder,if(network)"waiting_network" else "failed",uploadError)}
                // Other files remain independently retryable after a bad file or HTTP rejection.
            }
        }
    }
    fun retryDestination(id:String="") {
        if(id.isNotEmpty())retryIds.add(id)
        else dir.listFiles()?.filter {it.isDirectory}?.forEach {retryIds.add(it.name)}
        synchronized(uploadSignal) {uploadSignal.notifyAll()}
    }
    private fun request(base:String,key:String,method:String,path:String,body:JSONObject):JSONObject {
        transport?.let {return it(base,key,method,path,body)}
        val c=URL("$base/api/v1$path").openConnection() as HttpURLConnection
        try {c.requestMethod=method;c.connectTimeout=10000;c.readTimeout=20000;c.setRequestProperty("X-API-Key",key);c.setRequestProperty("Content-Type","application/json");c.doOutput=method!="GET"
            if(method!="GET")c.outputStream.use {it.write(body.toString().toByteArray())}
            check(c.responseCode in 200..299) { "服务器 ${c.responseCode}: ${c.errorStream?.bufferedReader()?.readText()?.take(250)}" }
            val text=c.inputStream.bufferedReader().readText();return if(text.isBlank())JSONObject() else JSONObject(text)
        } catch(e:java.io.IOException) {throw UploadNetworkException("网络不可达或传输中断，恢复后自动重试",e)} finally {c.disconnect()}
    }
    private fun save(s:JSONObject)=write(File(File(dir,s.getString("id")),"session.json"),s.toString())
    fun write(f:File,text:String) {synchronized(this) {
        val tmp=File(f.path+".new")
        tmp.outputStream().use {it.write(text.toByteArray(Charsets.UTF_8));it.fd.sync()}
        own(tmp)
        java.nio.file.Files.move(tmp.toPath(),f.toPath(),java.nio.file.StandardCopyOption.ATOMIC_MOVE,java.nio.file.StandardCopyOption.REPLACE_EXISTING)
    }}
    private fun own(f:File) { if(owner!=null) {android.system.Os.chown(f.path,owner,owner);android.system.Os.chmod(f.path,if(f.isDirectory)448 else 384)} }
}

internal class UploadNetworkException(message:String,cause:Throwable):java.io.IOException(message,cause)
