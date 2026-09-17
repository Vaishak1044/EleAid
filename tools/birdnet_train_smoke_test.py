"""Exercise the desktop application's BirdNET Train + Deploy code path."""

import multiprocessing
import os
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault("BIRDNET_APP_DATA", str(PROJECT_ROOT / "desktop" / "data" / "birdnet"))
sys.path.insert(0, str(PROJECT_ROOT / "desktop"))

import animal_sound_detector as detector  # noqa: E402


class ModelSelector:
    def get(self):
        return detector.MODEL_BIRDNET


def main():
    real_load_labels = detector.load_labels
    real_audio_files_in_folder = detector.audio_files_in_folder
    detector.load_labels = lambda: [
        label
        for label in real_load_labels()
        if real_audio_files_in_folder(detector.DATASET_DIR / detector.safe_label(label))
    ][:2]
    detector.audio_files_in_folder = lambda folder: real_audio_files_in_folder(folder)[:1]
    real_split_windows = detector.split_windows
    detector.split_windows = lambda audio, sr, window_sec, overlap: real_split_windows(
        audio, sr, window_sec, overlap
    )[:1]

    app = object.__new__(detector.App)
    app.model_type_var = ModelSelector()
    app.birdnet_encoder = None
    app.birdnet_backend = None
    app.birdnet_live_wav = PROJECT_ROOT / "desktop" / "data" / "tmp" / "birdnet_train_smoke.wav"
    app.birdnet_live_wav.parent.mkdir(parents=True, exist_ok=True)
    app.model_package = None
    app.pipeline = None
    errors = []

    def post(kind, message):
        print(f"[{kind}] {message}")
        if kind == "error":
            errors.append(message)

    app.post = post
    # Avoid replacing the user's deployed model during a smoke test.
    app.save_latest_model_package = lambda package: PROJECT_ROOT / "desktop" / "data" / "models" / "birdnet_smoke_test.joblib"

    app._train_thread(
        {
            "sample_rate": 48000,
            "window_sec": 3.0,
            "overlap": 0.5,
            "low_cut": 20.0,
            "high_cut": 5000.0,
        }
    )

    if errors:
        raise RuntimeError(errors[-1])
    if not app.model_package or app.model_package.get("feature_backend") != "birdnet_embeddings":
        raise RuntimeError("BirdNET training did not produce a BirdNET embedding package.")
    print(f"trained_labels={app.model_package.get('labels')}")
    print("birdnet-train-deploy-smoke=passed")


if __name__ == "__main__":
    multiprocessing.freeze_support()
    main()
