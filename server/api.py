#!/usr/bin/env python3
"""Small HTTP inference service for the Android companion client.

The full Tkinter application remains the authoring/monitoring tool for
Raspberry Pi and Windows. This service reuses its saved model package and
feature extraction code so Android can record audio and submit short WAV
windows without trying to package Tkinter or scikit-learn on Android.
"""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
import threading
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import Request, urlopen

import joblib
import numpy as np
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from desktop import animal_sound_detector as detector

app = FastAPI(title="EleAid Animal Sound Inference API", version="1.0.0")
_model_lock = threading.Lock()
_alert_lock = threading.Lock()
_cached_model_path: Path | None = None
_cached_package = None
_cached_engine = None
_last_event_label: str | None = None
_last_sms_time = 0.0
_last_tb_time = 0.0


def env_bool(name: str, default: bool = False) -> bool:
    return os.getenv(name, "1" if default else "0").strip().lower() in {"1", "true", "yes", "on"}


def env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except ValueError:
        return default


def require_api_key(request: Request) -> None:
    expected = os.getenv("API_KEY", "").strip()
    if expected and request.headers.get("X-API-Key", "") != expected:
        raise HTTPException(status_code=401, detail="Invalid or missing X-API-Key")


def resolve_model_path() -> Path:
    raw = os.getenv("ANIMAL_MODEL", "desktop/data/models/deployed_model.joblib")
    path = Path(raw).expanduser()
    return path if path.is_absolute() else PROJECT_ROOT / path


def load_model():
    global _cached_model_path, _cached_package, _cached_engine
    model_path = resolve_model_path()
    with _model_lock:
        if _cached_package is not None and _cached_model_path == model_path:
            return _cached_package, _cached_engine
        if not model_path.exists():
            raise FileNotFoundError(f"Model not found: {model_path}. Train and deploy one first.")
        package = joblib.load(model_path)
        engine = object.__new__(detector.App)
        engine.model_package = package
        engine.pipeline = package.get("pipeline")
        engine.birdnet_encoder = None
        engine.birdnet_backend = None
        engine.matt_retrain_interpreter = None
        engine.matt_retrain_input_details = None
        engine.matt_retrain_output_details = None
        engine.matt_retrain_labels = None
        engine.mobile_cnn_interpreter = None
        engine.mobile_cnn_input_details = None
        engine.mobile_cnn_output_details = None
        engine.mobile_cnn_labels = None
        detector.TMP_DIR.mkdir(parents=True, exist_ok=True)
        engine.birdnet_live_wav = detector.TMP_DIR / "android_api_birdnet_live.wav"
        _cached_model_path = model_path
        _cached_package = package
        _cached_engine = engine
        return package, engine


def normalize_host(raw_host: str) -> tuple[str, str]:
    raw = str(raw_host or "").strip()
    if not raw:
        return "", "https"
    candidate = raw if raw.startswith(("http://", "https://")) else "https://" + raw
    parsed = urlparse(candidate)
    host = parsed.netloc or parsed.path.split("/", 1)[0]
    scheme = parsed.scheme if parsed.scheme in {"http", "https"} else "https"
    return host.split(":", 1)[0], scheme


def predict_file(path: Path, target_override: str = ""):
    package, engine = load_model()
    cfg = dict(package.get("config") or {})
    backend = package.get("feature_backend", "handcrafted")
    sr, audio = detector.read_audio_file(path)
    target_sr = int(cfg.get("sample_rate", 48000))
    audio = detector.resample_if_needed(audio, sr, target_sr)
    sr = target_sr
    windows = detector.split_windows(
        audio,
        sr,
        float(cfg.get("window_sec", 3.0)),
        float(cfg.get("overlap", 0.5)),
    )
    if not windows:
        raise ValueError("Audio did not contain a usable window")

    all_classes = None
    all_probs = []
    for window in windows:
        if backend == "birdnet_embeddings":
            feature = engine.birdnet_encode_audio_window(window, sr, cfg).reshape(1, -1)
            probs = engine.pipeline.predict_proba(feature)[0]
            classes = list(engine.pipeline.classes_)
        elif backend == "matt_logic_tflite":
            classes, probs = engine.matt_retrain_predict_audio_window(window, sr)
        elif backend == "efficientnet_lite0_tflite":
            classes, probs = engine.mobile_cnn_predict_audio_window(window, sr)
        else:
            feature = detector.extract_features(
                window,
                sr,
                float(cfg.get("low_cut", 20.0)),
                float(cfg.get("high_cut", 5000.0)),
            ).reshape(1, -1)
            probs = engine.pipeline.predict_proba(feature)[0]
            classes = list(engine.pipeline.classes_)
        all_classes = classes
        all_probs.append(np.asarray(probs, dtype=np.float32))

    mean_probs = np.mean(np.stack(all_probs), axis=0)
    idx = int(np.argmax(mean_probs))
    label = str(all_classes[idx])
    confidence = float(mean_probs[idx])
    threshold = env_float("CONFIDENCE_THRESHOLD", 0.60)
    if threshold > 1.0:
        threshold /= 100.0
    target = target_override.strip() or os.getenv("ALERT_TARGET_LABEL", "").strip()
    valid = confidence >= max(0.0, min(1.0, threshold)) and (not target or label == target)
    pairs = sorted(
        ((str(cls), round(float(prob), 4)) for cls, prob in zip(all_classes, mean_probs)),
        key=lambda item: item[1],
        reverse=True,
    )
    return {
        "label": label,
        "confidence": round(confidence, 4),
        "valid": bool(valid),
        "threshold": round(threshold, 4),
        "target_label": target,
        "model_type": package.get("model_type", ""),
        "android_compatible": backend == "efficientnet_lite0_tflite",
        "probabilities": dict(pairs),
        "timestamp": datetime.now().isoformat(timespec="seconds"),
    }


def serial_read_until(ser, tokens: list[str], timeout: float) -> str:
    end = time.time() + timeout
    result = ""
    while time.time() < end:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            result += chunk.decode("utf-8", errors="ignore")
            if any(token in result for token in tokens):
                return result
        else:
            time.sleep(0.05)
    return result


def send_sms(message: str) -> None:
    if not env_bool("SMS_ENABLED"):
        return
    phone = os.getenv("SMS_PHONE", "").strip()
    port = os.getenv("SMS_PORT", "").strip()
    if not phone or not port:
        raise RuntimeError("SMS_ENABLED requires SMS_PHONE and SMS_PORT")
    try:
        import serial
    except ImportError as exc:
        raise RuntimeError("Install pyserial to enable server SMS") from exc
    baud = int(env_float("SMS_BAUD", 115200))
    with serial.Serial(port=port, baudrate=baud, timeout=0.5, write_timeout=5) as ser:
        def at(command: str, expected: str = "OK"):
            ser.reset_input_buffer()
            ser.write((command + "\r").encode("ascii", errors="ignore"))
            ser.flush()
            response = serial_read_until(ser, [expected, "ERROR"], 5)
            if expected not in response:
                raise RuntimeError(f"SIM7600 command failed: {command}: {response.strip()}")

        at("AT")
        at("ATE0")
        at("AT+CMGF=1")
        at('AT+CSCS="GSM"')
        ser.reset_input_buffer()
        ser.write((f'AT+CMGS="{phone}"\r').encode("ascii", errors="ignore"))
        ser.flush()
        if ">" not in serial_read_until(ser, [">", "ERROR"], 5):
            raise RuntimeError("SIM7600 did not provide SMS prompt")
        ser.write(message[:300].replace("\n", " ").encode("ascii", errors="ignore") + b"\x1a")
        ser.flush()
        if "+CMGS:" not in serial_read_until(ser, ["+CMGS:", "OK", "ERROR"], 20):
            raise RuntimeError("SIM7600 did not confirm SMS")


def send_thingsboard(result: dict) -> None:
    if not env_bool("TB_ENABLED"):
        return
    host, scheme = normalize_host(os.getenv("TB_HOST", ""))
    token = os.getenv("TB_TOKEN", "").strip()
    if not host or not token:
        raise RuntimeError("TB_ENABLED requires TB_HOST and TB_TOKEN")
    payload = {
        "animal_prediction_label": result["label"],
        "animal_prediction_confidence": result["confidence"],
        "animal_prediction_valid": result["valid"],
        "animal_confirmed_label": result["label"] if result["valid"] else "",
        "animal_model_type": result["model_type"],
        "animal_client_time": result["timestamp"],
    }
    payload.update({"animal_prob_" + re.sub(r"[^A-Za-z0-9]+", "_", key).strip("_"): value * 100 for key, value in result["probabilities"].items()})
    url = f"{scheme}://{host}/api/v1/{token}/telemetry"
    request = Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=35) as response:
        if not 200 <= int(response.status) < 300:
            raise RuntimeError(f"ThingsBoard HTTP {response.status}")


def dispatch_alerts(result: dict) -> dict:
    global _last_event_label, _last_sms_time, _last_tb_time
    now = time.time()
    response = {"sms": "not triggered", "thingsboard": "not triggered"}
    with _alert_lock:
        if not result["valid"]:
            _last_event_label = None
        if result["valid"] and env_bool("SMS_ENABLED") and result["label"] != _last_event_label:
            send_sms(f"Detected animal sound: {result['label']} ({result['confidence'] * 100:.1f}%)")
            _last_event_label = result["label"]
            _last_sms_time = now
            response["sms"] = "sent"
        elif result["valid"] and env_bool("SMS_ENABLED"):
            response["sms"] = "deduplicated"

        interval = max(1.0, env_float("TB_INTERVAL_SEC", 10.0))
        if env_bool("TB_ENABLED") and now - _last_tb_time >= interval:
            send_thingsboard(result)
            _last_tb_time = now
            response["thingsboard"] = "sent"
        elif env_bool("TB_ENABLED"):
            response["thingsboard"] = "rate-limited"
    return response


@app.get("/health")
def health(request: Request):
    require_api_key(request)
    path = resolve_model_path()
    model_type = ""
    android_compatible = False
    if path.exists():
        try:
            package = joblib.load(path)
            model_type = package.get("model_type", "")
            android_compatible = package.get("feature_backend") == "efficientnet_lite0_tflite"
        except Exception:
            pass
    return {
        "ok": True,
        "model_path": str(path),
        "model_available": path.exists(),
        "model_type": model_type,
        "android_compatible": android_compatible,
    }


@app.post("/predict")
async def predict(request: Request, audio: UploadFile = File(...), target_label: str = Form("")):
    require_api_key(request)
    suffix = Path(audio.filename or "audio.wav").suffix.lower() or ".wav"
    if suffix not in detector.SUPPORTED_AUDIO_EXTS:
        raise HTTPException(status_code=400, detail="Only WAV and MP3 files are supported")
    try:
        content = await audio.read()
        if not content:
            raise ValueError("Uploaded audio is empty")
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as temp:
            temp.write(content)
            temp_path = Path(temp.name)
        try:
            result = predict_file(temp_path, target_label)
            result["alerts"] = dispatch_alerts(result)
            return result
        finally:
            temp_path.unlink(missing_ok=True)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("server.api:app", host=os.getenv("API_HOST", "0.0.0.0"), port=int(os.getenv("API_PORT", "8000")))
