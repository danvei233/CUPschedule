package cn.blackbook.blackbook.recording

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

internal object LocalRecordings {
    // Deliberate whitelist: session manifests contain API credentials.
    fun list(dir: File): JSONArray {
        val result=JSONArray()
        val config=runCatching {JSONObject(File(dir,"config.json").readText())}.getOrDefault(JSONObject())
        dir.listFiles()?.filter {it.isDirectory}?.forEach {folder ->
            runCatching {
                val s=JSONObject(File(folder,"session.json").readText())
                val row=JSONObject()
                for(key in listOf("id","course_id","title","started_at","samples","total_chunks","acked","finished","interrupted","uploaded","uploaded_at","capture_error")) {
                    if(s.has(key))row.put(key,s.get(key))
                }
                val transfer=runCatching {JSONObject(File(folder,"upload-state.json").readText())}.getOrDefault(JSONObject())
                row.put("sync_state",if(s.optBoolean("uploaded")) "uploaded" else transfer.optString("state","local"))
                row.put("sync_error",transfer.optString("error"))
                row.put("sync_updated_at",transfer.optLong("updated_at"))
                val destination=s.optString("base_url").trimEnd('/')
                row.put("destination_matches",destination.isEmpty() || destination==config.optString("base_url").trimEnd('/'))
                result.put(row)
            }
        }
        return result
    }
}
