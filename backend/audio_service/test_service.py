"""No CUDA, torch, model imports, model downloads, or listening server required."""
import io
import os
import unittest
import wave

os.environ["BLACKBOOK_AUDIO_MOCK"] = "1"
os.environ["BLACKBOOK_AUDIO_KEY"] = "test-audio-key"

from fastapi.testclient import TestClient
from service import app, models


def wav(frames=16000):
    out = io.BytesIO()
    with wave.open(out, "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(16000)
        audio.writeframes(b"\x01\x00" * frames)
    return out.getvalue()


class AudioTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.headers = {"X-Service-Key": "test-audio-key"}
        models.unload()

    def test_auth_and_explicit_loading(self):
        self.assertEqual(self.client.get("/models/status").status_code, 401)
        self.assertFalse(self.client.get("/models/status", headers=self.headers).json()["loaded"])
        self.assertEqual(self.client.post("/transcribe?recording_id=a", headers=self.headers, content=wav()).status_code, 503)
        self.assertEqual(self.client.post("/models/load", headers=self.headers).status_code, 200)
        out = self.client.post("/transcribe?recording_id=a&final=true", headers=self.headers, content=wav())
        self.assertEqual(out.status_code, 200)
        self.assertEqual(out.json()["segments"][0]["end"], 1)
        self.assertTrue(out.json()["segments"][0]["final"])

    def test_incremental_retry_and_restart(self):
        models.load()
        def send(offset):
            return self.client.post(f"/transcribe?recording_id=b&offset={offset}", headers=self.headers, content=wav())
        self.assertEqual(send(0).json()["segments"][0]["end"], 1)
        self.assertEqual(send(0).json()["segments"][0]["end"], 1)
        self.assertEqual(send(16000).json()["segments"][0]["end"], 2)
        models.unload()
        models.load()
        self.assertIn("replay_required", send(32000).text)
        self.assertEqual(send(0).status_code, 200)

    def test_websocket_auth_and_mock_events(self):
        models.load()
        with self.client.websocket_connect("/stream/c", headers=self.headers) as ws:
            ws.send_bytes(wav())
            self.assertEqual(ws.receive_json()["segments"][0]["speaker"], "说话人 1")


if __name__ == "__main__":
    unittest.main()
