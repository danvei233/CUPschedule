package cn.blackbook.blackbook.recording

import android.content.Context
import android.os.PowerManager

/** Framework access needed by the standalone, root-owned app_process entry point. */
object RecorderRuntime {
    val context:Context by lazy {
        val at=Class.forName("android.app.ActivityThread")
        val thread=at.getMethod("systemMain").invoke(null)
        at.getMethod("getSystemContext").invoke(thread) as Context
    }
    private var wake:PowerManager.WakeLock?=null
    @Synchronized fun keepAwake(enabled:Boolean) {
        if(enabled) {
            if(wake==null)wake=context.getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"blackbook:root-recording").apply {setReferenceCounted(false)}
            // Renewed by the daemon. Automatically expires if the process stalls.
            wake?.acquire(120000)
        } else if(wake?.isHeld==true)wake?.release()
    }
}
