package cn.blackbook.blackbook.recording

import android.app.*
import android.content.Intent
import android.os.IBinder
import cn.blackbook.blackbook.R
import java.io.File

class RecorderService: Service() {
    private var wake:android.os.PowerManager.WakeLock?=null
    companion object { @Volatile var engine:RecorderEngine?=null }
    private lateinit var notification:Notification
    private var ownedEngine:RecorderEngine?=null
    override fun onCreate() {
        super.onCreate()
        wake=getSystemService(android.os.PowerManager::class.java).newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK,"blackbook:recording").apply {acquire(12*60*60*1000L)}
        val nm=getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("recording","课堂录音",NotificationManager.IMPORTANCE_LOW))
        val stop=PendingIntent.getService(this,42,Intent(this,RecorderService::class.java).setAction("stop"),PendingIntent.FLAG_IMMUTABLE)
        notification=Notification.Builder(this,"recording").setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("课堂录音服务").setContentText("正在录音或同步音频")
            .addAction(Notification.Action.Builder(null,"停止录音",stop).build()).setOngoing(true).build()
        androidx.core.app.ServiceCompat.startForeground(this,4201,notification,android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        try {ownedEngine=RecorderEngine(File(filesDir,"recording"));engine=ownedEngine} catch(t:Exception) {
            android.util.Log.e("BlackbookRecorder","无法启动同步服务",t)
            stopSelf()
        }
    }
    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int {
        try { when(intent?.action) {
            "start" -> {
                androidx.core.app.ServiceCompat.startForeground(this,4201,notification,android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
                engine?.start(intent.getStringExtra("course_id") ?: "misc")
            }
            "sync" -> engine?.retryDestination(intent.getStringExtra("recording_id") ?: "")
            "stop" -> engine?.stop()
            "pause" -> engine?.pause(true)
            "resume" -> engine?.pause(false)
        }} catch(t:Throwable) { engine?.write(File(filesDir,"recording/service-error.txt"),t.toString()) }
        return START_NOT_STICKY
    }
    override fun onDestroy(){
        val closing=ownedEngine
        Thread {
            try {closing?.close()} catch(t:Exception) {
                android.util.Log.e("BlackbookRecorder","关闭录音同步服务失败",t)
            } finally {
                if(engine===closing)engine=null
                if(wake?.isHeld==true)wake?.release()
            }
        }.start()
        super.onDestroy()
    }
    override fun onBind(intent:Intent?):IBinder?=null
    override fun onTimeout(startId:Int,fgsType:Int) {stopSelf()}
}
