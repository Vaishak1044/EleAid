# EleAid Acoustic Sound Classifier

EleAid is an acoustic sound-classification system for Raspberry Pi and Windows, with an independently deployable Android application.

The project has two supported runtime modes:

1. **RPi/Windows desktop:** the Python/Tkinter application records labeled audio, trains a model, performs continuous microphone inference, sends SIM7600 SMS alerts, and publishes ThingsBoard telemetry.
2. **Android standalone:** the Flutter app packages the trained EfficientNet-Lite0 TFLite model, records 3-second WAV windows, performs inference locally, and can publish ThingsBoard telemetry directly. The Play build uses the phone’s SMS composer; the private field build can send automatically through the phone SIM.

Android uses only the exported EfficientNet-Lite0 TFLite model. Tkinter, scikit-learn joblib models, BirdNET, and the Python inference API are not Android dependencies.

## Quick start

For complete Windows, Raspberry Pi, FFmpeg, optional-model, Android, signing,
and troubleshooting instructions, read [docs/USER_GUIDE.md](docs/USER_GUIDE.md).

### Raspberry Pi or Windows desktop

```text
python -m venv .venv
# Windows: .\.venv\Scripts\Activate.ps1
# RPi/Linux: source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r desktop/requirements.txt
python desktop/animal_sound_detector.py
```

For MP3 import, install the FFmpeg Windows binary and add its `bin` directory
to PATH, or install the Debian `ffmpeg` package on Raspberry Pi. For optional
BirdNET, TensorFlow/Matt Logic, EfficientNet-Lite0 Mobile CNN/TFLite, and SMS
support, install the matching packages described in [the user guide](docs/USER_GUIDE.md).
Do not install every optional backend unless your platform has compatible wheels.
Android supports only the EfficientNet-Lite0 Mobile CNN/TFLite model.

### Optional inference API

The Python API remains available for remote clients, but it is not required by the standalone Android APK:

```text
python -m pip install -r server/requirements.txt
python -m pip install -r desktop/requirements.txt
python -m server.api
```

### Android

```text
cd android
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter devices
```

The desktop app’s **Training** tab provides separate **Build Play-compatible APK**
and **Build Field APK (automatic SIM SMS)** buttons. Both package the trained
Mobile CNN model into a standalone release APK; no inference API URL or API key
is used. The Play build uses user-confirmed SMS composition, while the field
build retains automatic SIM SMS.

## Repository layout

```text
desktop/    Full RPi/Windows authoring, monitoring, SMS, and ThingsBoard app
server/     FastAPI inference service used by Android
android/    Flutter Android companion client
models/     Public model packaging notes; trained artifacts stay out of Git
docs/       Complete installation, training, deployment, and troubleshooting guide
```

Do not commit phone numbers, SIM credentials, ThingsBoard access tokens, datasets containing personal information, or trained model artifacts unless you have explicitly chosen to publish them.

The original ZIP contained several historical revisions. The public desktop entry point is the cleaned v6.4 implementation copied to `desktop/animal_sound_detector.py`; the stale execution note is not used.
