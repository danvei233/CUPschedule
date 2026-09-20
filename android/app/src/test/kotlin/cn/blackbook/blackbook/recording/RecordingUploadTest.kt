package cn.blackbook.blackbook.recording

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class RecordingUploadTest {
    private fun seed(dir:File,id:String) {
        File(dir,id).mkdirs()
        repeat(3) {File(dir,"$id/$it.pcm").writeBytes(byteArrayOf(1,0,2,0))}
        File(dir,"$id/session.json").writeText(JSONObject().put("id",id).put("course_id","misc").put("title",id).put("started_at","2026-09-20T10:00:00Z").put("samples",6).put("total_chunks",3).put("acked",-1).put("finished",true).put("base_url","").put("api_key","").toString())
    }
    private fun config(dir:File) {File(dir,"config.json").writeText("""{"base_url":"http://test","api_key":"private-test-key"}""")}
    private fun until(predicate:()->Boolean) {
        val deadline=System.currentTimeMillis()+8000
        while(!predicate() && System.currentTimeMillis()<deadline)Thread.sleep(25)
        assertTrue("upload state did not converge",predicate())
    }
    private fun manifest(dir:File,id:String)=JSONObject(File(dir,"$id/session.json").readText())
    private fun state(dir:File,id:String)=runCatching {JSONObject(File(dir,"$id/upload-state.json").readText()).getString("state")}.getOrDefault("")

    @Test fun offlineQueueUploadsAfterReconnectAndDoesNotExposeCredentials() {
        val dir=Files.createTempDirectory("upload-offline").toFile()
        config(dir);seed(dir,"one")
        val online=AtomicBoolean(false)
        val posts=AtomicInteger()
        val engine=RecorderEngine(dir,transport={_,_,method,path,body ->
            if(!online.get())throw UploadNetworkException("offline",java.net.ConnectException())
            if(path.endsWith("/chunks") && method=="POST") {assertTrue(body.has("sha256"));posts.incrementAndGet()}
            if(path=="/recordings") {assertFalse(body.has("api_key"));assertFalse(body.has("base_url"))}
            if(method=="GET")JSONObject().put("chunks",JSONArray()) else JSONObject()
        })
        try {
            until {state(dir,"one")=="waiting_network"}
            assertFalse(manifest(dir,"one").optBoolean("uploaded"))
            assertTrue(File(dir,"one/0.pcm").exists())
            online.set(true);engine.retryDestination("one")
            until {manifest(dir,"one").optBoolean("uploaded")}
            assertEquals(3,posts.get())
            val public=LocalRecordings.list(dir).getJSONObject(0)
            assertEquals("uploaded",public.getString("sync_state"))
            assertFalse(public.has("api_key"));assertFalse(public.has("base_url"))
        } finally {engine.close();dir.deleteRecursively()}
    }

    @Test fun restartTrustsServerChunksAndWaitsForFinalVerification() {
        val dir=Files.createTempDirectory("upload-resume").toFile()
        config(dir);seed(dir,"one")
        val verified=AtomicBoolean(false)
        val posts=AtomicInteger()
        val transport={_:String,_:String,method:String,path:String,_:JSONObject ->
            if(path.endsWith("/complete") && !verified.get())throw IllegalStateException("verification failed")
            if(path.endsWith("/chunks") && method=="POST")posts.incrementAndGet()
            if(method=="GET")JSONObject().put("chunks",JSONArray().put(JSONObject().put("seq",0)).put(JSONObject().put("seq",1)).put(JSONObject().put("seq",2))) else JSONObject()
        }
        val first=RecorderEngine(dir,transport=transport)
        try {until {state(dir,"one")=="failed"};assertFalse(manifest(dir,"one").optBoolean("uploaded"))} finally {first.close()}
        verified.set(true)
        val second=RecorderEngine(dir,transport=transport)
        try {until {manifest(dir,"one").optBoolean("uploaded")};assertEquals(0,posts.get())}
        finally {second.close();dir.deleteRecursively()}
    }

    @Test fun failedRecordingDoesNotBlockAnotherRecording() {
        val dir=Files.createTempDirectory("upload-independent").toFile()
        config(dir);seed(dir,"bad");seed(dir,"good")
        val engine=RecorderEngine(dir,transport={_,_,method,_,body ->
            if(body.optString("id")=="bad")throw IllegalStateException("HTTP 400")
            if(method=="GET")JSONObject().put("chunks",JSONArray()) else JSONObject()
        })
        try {until {manifest(dir,"good").optBoolean("uploaded")};assertFalse(manifest(dir,"bad").optBoolean("uploaded"))}
        finally {engine.close();dir.deleteRecursively()}
    }
}
