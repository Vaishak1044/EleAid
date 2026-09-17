"""Validate the cached BirdNET acoustic encoder outside the Tk GUI."""

import multiprocessing
import os
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault("BIRDNET_APP_DATA", str(PROJECT_ROOT / "desktop" / "data" / "birdnet"))
sys.path.insert(0, str(PROJECT_ROOT / "desktop"))

import animal_sound_detector as detector  # noqa: E402


def main():
    audio_files = sorted(
        path
        for path in (PROJECT_ROOT / "desktop" / "data" / "dataset").rglob("*")
        if path.suffix.lower() in {".wav", ".mp3"}
    )
    if not audio_files:
        raise RuntimeError("No WAV/MP3 sample was found in desktop/data/dataset.")

    app = object.__new__(detector.App)
    app.birdnet_encoder = None
    app.birdnet_backend = None
    app.birdnet_live_wav = PROJECT_ROOT / "desktop" / "data" / "tmp" / "birdnet_smoke.wav"
    app.birdnet_live_wav.parent.mkdir(parents=True, exist_ok=True)

    sample_rate, audio = detector.read_audio_file(audio_files[0])
    result = app.birdnet_encode_audio_window(
        audio,
        sample_rate,
        {"low_cut": 20.0, "high_cut": 5000.0},
    )
    values = detector._coerce_numeric_array(result)
    print(f"backend={app.birdnet_backend}")
    print(f"sample={audio_files[0]}")
    print(f"embedding_shape={values.shape}")
    if values.size < 8:
        raise RuntimeError("BirdNET returned too few values.")
    print("birdnet-smoke=passed")


if __name__ == "__main__":
    multiprocessing.freeze_support()
    main()
