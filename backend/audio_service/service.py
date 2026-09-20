"""Independent audio worker. Importing this module never downloads or loads models."""
import asyncio
import gc
import io
import os
import secrets
import threading
import time
import wave
from contextlib import asynccontextmanager
from urllib.parse import unquote_plus

from fastapi import FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect


class Models:
    def __init__(self):
        self.lock = threading.RLock()
        self.whisper = None
        self.sessions = {}
        self.busy = False
        self.last_error = ""
        self.mock = os.getenv("BLACKBOOK_AUDIO_MOCK", "0") == "1"
        self.segmentation = None
        self.embedding = None

    def status(self):
        return {"loaded": self.whisper is not None, "busy": self.busy,
                "mock": self.mock, "model": "large-v3-turbo", "error": self.last_error,
                "sessions": len(self.sessions)}

    def load(self):
        with self.lock:
            if self.whisper is not None:
                return self.status()
            if self.mock:
                self.whisper = "mock"
            else:
                import ctranslate2
                from faster_whisper import WhisperModel
                if "float16" not in ctranslate2.get_supported_compute_types("cuda"):
                    raise RuntimeError("CUDA GPU does not support float16; check the V100 driver/runtime")
                self.whisper = WhisperModel(os.getenv("BLACKBOOK_WHISPER_MODEL", "large-v3-turbo"),
                                           device="cuda", compute_type="float16",
                                           download_root=os.getenv("BLACKBOOK_MODEL_DIR"))
                # Fail at load time if pyannote access/model dependencies are unavailable.
                self._pipeline()
            self.last_error = ""
            return self.status()

    def _pipeline(self):
        from diart import SpeakerDiarization, SpeakerDiarizationConfig
        from diart.models import SegmentationModel, EmbeddingModel
        import torch
        token = os.getenv("HF_TOKEN")
        if self.segmentation is None:
            self.segmentation = SegmentationModel.from_pretrained("pyannote/segmentation-3.0", use_hf_token=token)
            self.embedding = EmbeddingModel.from_pretrained("pyannote/embedding", use_hf_token=token)
        return SpeakerDiarization(SpeakerDiarizationConfig(
            segmentation=self.segmentation, embedding=self.embedding, duration=5, step=0.5,
            latency=5, device=torch.device("cuda")))

    def unload(self):
        # Do not tear down models used by an active call.
        if not self.lock.acquire(blocking=False):
            raise RuntimeError("Inference is active; stop or wait for tasks before unloading")
        try:
            self.sessions.clear()
            self.whisper = None
            self.segmentation = None
            self.embedding = None
            gc.collect()
            if not self.mock:
                import torch
                torch.cuda.empty_cache()
            return self.status()
        finally:
            self.lock.release()

    def transcribe(self, recording_id, data, final, prompt, offset=0):
        with self.lock:
            if self.whisper is None:
                raise RuntimeError("Models are unloaded; load them in settings first")
            self.busy = True
            try:
                with wave.open(io.BytesIO(data), "rb") as wav:
                    if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) != (1, 2, 16000):
                        raise ValueError("Expected mono PCM16 at 16000 Hz")
                    pcm = wav.readframes(wav.getnframes())
                session = self.sessions.get(recording_id)
                if not final:
                    if session is None:
                        if offset:
                            raise RuntimeError("replay_required: audio worker lost session")
                        session = {"pipeline": None, "offset": 0, "turns": [], "seen": time.time(), "pcm": bytearray()}
                        self.sessions[recording_id] = session
                    audio = session["pcm"]
                    if offset * 2 > len(audio):
                        raise RuntimeError("replay_required: missing audio prefix")
                    # Idempotent replay of an already processed request.
                    existing = audio[offset * 2:offset * 2 + len(pcm)]
                    if existing and bytes(existing) != pcm[:len(existing)]:
                        raise ValueError("Conflicting audio at sample offset")
                    audio.extend(pcm[len(existing):])
                    pcm = audio
                seconds = len(pcm) / 32000
                if self.mock:
                    if final:
                        self.sessions.pop(recording_id, None)
                    return {"segments": [{"id": "0", "start": 0, "end": seconds,
                                          "text": "模拟课堂转写，仅用于链路测试。", "speaker": "说话人 1",
                                          "version": 1, "final": final}]}
                import numpy as np
                from pyannote.core import SlidingWindow, SlidingWindowFeature
                samples = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768
                diarization_samples = np.pad(samples, (0, 80000)) if final else samples
                # Replaying the canonical audio after restart rebuilds the online clustering state.
                if session is None:
                    session = {"pipeline": self._pipeline(), "offset": 0, "turns": [], "seen": time.time()}
                    self.sessions[recording_id] = session
                if session["pipeline"] is None:
                    session["pipeline"] = self._pipeline()
                session["seen"] = time.time()
                while session["offset"] + 80000 <= len(diarization_samples):
                    offset = session["offset"]
                    feature = SlidingWindowFeature(diarization_samples[offset:offset + 80000, None],
                                                   SlidingWindow(start=offset / 16000, duration=1 / 16000, step=1 / 16000))
                    for annotation, _ in session["pipeline"]([feature]):
                        for turn, _, speaker in annotation.itertracks(yield_label=True):
                            labels = session.setdefault("labels", {})
                            label = labels.setdefault(str(speaker), f"说话人 {len(labels) + 1}")
                            session["turns"].append((turn.start, min(turn.end, seconds), label))
                    session["offset"] += 8000
                # Align to a fixed window boundary, avoiding shifting provisional IDs on each request.
                start = 0 if final else max(0, int((seconds - 15) // 5) * 5)
                result, _ = self.whisper.transcribe(samples[int(start * 16000):], language="zh",
                                                     initial_prompt=prompt or None, vad_filter=True,
                                                     word_timestamps=True, beam_size=5)
                segments = []
                for index, segment in enumerate(result):
                    begin, end = start + segment.start, start + segment.end
                    overlaps = {}
                    for left, right, label in session["turns"]:
                        overlap = max(0, min(end, right) - max(begin, left))
                        overlaps[label] = overlaps.get(label, 0) + overlap
                    speaker = max(overlaps, key=overlaps.get) if overlaps and max(overlaps.values()) > 0 else "待识别"
                    segments.append({"id": str(index) if final else f"live-{start}-{index}",
                                     "start": begin, "end": end, "text": segment.text,
                                     "speaker": speaker, "version": 1, "final": final})
                if final:
                    self.sessions.pop(recording_id, None)
                # Idle sessions can always be reconstructed from durable Go audio.
                for key in list(self.sessions):
                    if time.time() - self.sessions[key]["seen"] > 1800:
                        del self.sessions[key]
                return {"segments": segments}
            except Exception as exc:
                self.last_error = str(exc)
                raise
            finally:
                self.busy = False


models = Models()


@asynccontextmanager
async def lifespan(app):
    if not os.getenv("BLACKBOOK_AUDIO_KEY"):
        raise RuntimeError("BLACKBOOK_AUDIO_KEY is required")
    if os.getenv("BLACKBOOK_AUDIO_AUTOLOAD", "0") == "1":
        await asyncio.to_thread(models.load)
    yield


app = FastAPI(title="Blackbook audio worker", lifespan=lifespan)


def authenticate(key):
    expected = os.getenv("BLACKBOOK_AUDIO_KEY", "")
    if not expected or not secrets.compare_digest(key or "", expected):
        raise HTTPException(401, "Invalid service key")


@app.middleware("http")
async def authentication(request: Request, call_next):
    from fastapi.responses import JSONResponse
    try:
        authenticate(request.headers.get("X-Service-Key"))
    except HTTPException:
        return JSONResponse({"error": "Invalid service key"}, status_code=401)
    return await call_next(request)


@app.get("/models/status")
def status():
    return models.status()


@app.post("/models/{action}")
async def control(action: str):
    try:
        if action == "load":
            return await asyncio.to_thread(models.load)
        if action == "unload":
            return await asyncio.to_thread(models.unload)
        if action == "reload":
            await asyncio.to_thread(models.unload)
            return await asyncio.to_thread(models.load)
        raise HTTPException(400, "Unknown model action")
    except Exception as exc:
        models.last_error = str(exc)
        if action in ("load", "reload"):
            models.whisper = None
        raise HTTPException(409, str(exc)) from exc


@app.post("/transcribe")
async def transcribe(request: Request, recording_id: str, final: bool = False, offset: int = 0):
    if offset < 0:
        raise HTTPException(400, "Invalid offset")
    data = bytearray()
    async for chunk in request.stream():
        data.extend(chunk)
        if len(data) > 1024 * 1024 * 1024:
            raise HTTPException(413, "Audio exceeds 1 GiB")
    try:
        return await asyncio.to_thread(models.transcribe, recording_id, data, final,
                                       unquote_plus(request.headers.get("X-Transcription-Prompt", "")), offset)
    except Exception as exc:
        raise HTTPException(503, str(exc)) from exc


@app.websocket("/stream/{recording_id}")
async def stream(ws: WebSocket, recording_id: str):
    try:
        authenticate(ws.headers.get("X-Service-Key"))
    except HTTPException:
        await ws.close(code=1008)
        return
    await ws.accept()
    try:
        while True:
            # Canonical WAV snapshots. Public durable/reconnect protocol belongs to Go.
            data = await ws.receive_bytes()
            if len(data) > 1024 * 1024 * 1024:
                await ws.close(code=1009)
                return
            out = await asyncio.to_thread(models.transcribe, recording_id, data, False, "")
            await ws.send_json(out)
    except WebSocketDisconnect:
        pass
