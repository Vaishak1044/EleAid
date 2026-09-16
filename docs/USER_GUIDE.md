# EleAid complete user and deployment guide

This guide describes the verified EleAid workflow for Windows, Raspberry Pi OS,
and Android. Read the platform section for the device on which you are working.

## 1. What the project does

EleAid has three related parts:

1. The Windows/Raspberry Pi desktop application records labeled sound samples,
   trains models, performs continuous local inference, sends SIM7600 SMS alerts,
   and uploads telemetry to ThingsBoard.
2. The optional Python inference API exposes a trained desktop model to remote
   clients. It is not required by the standalone Android application.
3. The Android Flutter application packages one trained
   **EfficientNet-Lite0 Mobile CNN/TFLite** model, records audio on the phone,
   performs inference locally, and sends telemetry directly to ThingsBoard.

Android does not train a model. Training and Android model export are done on
Windows or Raspberry Pi, normally Windows because TensorFlow installation is
usually easier there.

## 2. Supported models and features

| Model or feature | Windows | Raspberry Pi | Android |
|---|---:|---:|---:|
| Random Forest | Yes | Yes | No |
| SVM-RBF | Yes | Yes | No |
| BirdNET embeddings + Logistic Regression | Yes, if BirdNET supports the Python version | Depends on compatible wheels | No |
| Matt Logic EfficientNet retraining | Yes | Depends on TensorFlow wheels | No |
| EfficientNet-Lite0 Mobile CNN/TFLite | Yes | Yes, if TensorFlow dependencies install | **Only supported model** |
| SIM7600 automatic SMS | Yes | Yes | No |
| Phone-SIM automatic SMS | No | No | Field APK only |
| Phone-SIM user-confirmed SMS composer | No | No | Play APK |
| Direct ThingsBoard upload | Yes | Yes | Yes |

The Android model requires these exact training settings:

- Sample rate: `48000` Hz
- Window length: `3.0` seconds
- Input model: `EfficientNet-Lite0 Mobile CNN/TFLite`

## 3. Repository layout

```text
desktop/                 Python desktop application and runtime data
desktop/data/dataset/    Writable labeled audio dataset
desktop/data/models/     Generated model artifacts; do not publish by default
desktop/sample_data/     Optional licensed starter recordings
desktop/requirements.txt Base Python dependencies
desktop/requirements-mobile.txt Mobile CNN training dependencies
server/                  Optional FastAPI inference service
android/                 Flutter project
android/assets/          Model and label files copied into the APK
android/android/         Android Gradle project and signing configuration
models/                  Model packaging notes
docs/                    Documentation
```

Run commands from the repository root unless a command first changes directory.
On Windows, the repository root in the examples is:

```text
D:\Projects\EleAid\Codex version of EleAid
```

## 4. Windows installation

### 4.1 Install required software

Install:

- 64-bit Python, preferably Python 3.10 or 3.11 for the TensorFlow/BirdNET
  combinations used by this project;
- a working microphone and its Windows driver;
- Git, if you are cloning the public repository;
- FFmpeg only if you will import MP3 files or other formats converted by
  `pydub`.

Do not start the Python application before installing its dependencies.

### 4.2 Create and activate the Python environment

Open PowerShell in the repository root:

```powershell
cd "D:\Projects\EleAid\Codex version of EleAid"
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
```

The activation command has one leading dot and one backslash. Do not type
`python desktop\animal_sound_detector.py` before the environment is activated.

If PowerShell refuses to run the activation script, run this once as your
normal user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Then activate again:

```powershell
.\.venv\Scripts\Activate.ps1
```

You can also avoid activation and use the environment directly:

```powershell
.\.venv\Scripts\python.exe -m pip install --upgrade pip
```

If `C:\Python311\python.exe -m pip` reports `No module named pip`, use
`py -3 -m venv .venv` as above. The new virtual environment includes its own
pip and should be used for all project commands.

### 4.3 Install Python dependencies

Base desktop dependencies:

```powershell
python -m pip install -r desktop\requirements.txt
```

Optional server dependencies, only if you will run the Python API:

```powershell
python -m pip install -r server\requirements.txt
```

Mobile CNN dependencies, required to train/export the Android model:

```powershell
python -m pip install -r desktop\requirements-mobile.txt
```

SIM7600 SMS support:

```powershell
python -m pip install pyserial
```

The mobile requirements install TensorFlow, TensorFlow Hub, `tf-keras`, and
librosa. The first Mobile CNN training run downloads the EfficientNet-Lite0
feature-vector backbone from TensorFlow Hub, so internet access is required.

### 4.4 Install FFmpeg on Windows

The source-code ZIP named something like `ffmpeg-9.0.1` contains folders such
as `libavcodec`, `libavformat`, and `configure`. That is not a Windows binary
package and will not contain `ffmpeg.exe` unless you compile FFmpeg yourself.

Use a prebuilt Windows package from the Windows builds linked by the
[official FFmpeg download page](https://ffmpeg.org/download.html). The
[Gyan Windows builds page](https://www.gyan.dev/ffmpeg/builds/) is one of the
Windows build sources linked there.

Download an essentials or full Windows ZIP, then extract it so the final paths
look like:

```text
C:\ffmpeg\bin\ffmpeg.exe
C:\ffmpeg\bin\ffprobe.exe
```

If extraction produces a nested folder, add the nested `bin` directory that
actually contains `ffmpeg.exe`, for example:

```text
C:\ffmpeg-9.0.1-essentials_build\bin
```

Add that `bin` directory to the Windows user PATH:

1. Search Windows for **Environment Variables**.
2. Open **Edit the system environment variables**.
3. Select **Environment Variables**.
4. Under **User variables**, select **Path → Edit → New**.
5. Add the directory containing `ffmpeg.exe`, such as `C:\ffmpeg\bin`.
6. Confirm all dialogs.
7. Close and reopen PowerShell and the desktop application.

Verify from a new PowerShell window:

```powershell
where.exe ffmpeg
ffmpeg -version
```

Alternatively, Windows Package Manager can install an essentials build:

```powershell
winget install "FFmpeg (Essentials Build)"
```

The FFmpeg warning is mainly relevant to MP3 import/conversion. WAV recording
and WAV-only workflows may continue without it.

### 4.5 Start the Windows desktop app

From the repository root, with `.venv` activated:

```powershell
python desktop\animal_sound_detector.py
```

The application stores runtime data under `desktop\data\`. Do not put tokens,
phone numbers, raw recordings, or trained artifacts into a public Git commit.

## 5. Raspberry Pi OS installation

Use a current 64-bit Raspberry Pi OS when possible. TensorFlow, BirdNET, and
TFLite runtime wheels are platform-specific; if a package has no compatible
wheel for the selected Python version, that model cannot be installed unchanged
on that Pi.

Install system packages:

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-tk portaudio19-dev libsndfile1 ffmpeg curl
```

Create the environment and install the base application:

```bash
cd /path/to/EleAid
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r desktop/requirements.txt
```

Install optional dependencies only for the features you will use:

```bash
python -m pip install -r desktop/requirements-mobile.txt
python -m pip install pyserial
```

The Mobile CNN dependencies may require a Pi/Python combination with available
TensorFlow wheels. If installation fails because TensorFlow has no wheel for
the platform, train the model on Windows and use the exported model for the
deployment path supported by the project.

Start the application:

```bash
python desktop/animal_sound_detector.py
```

For a USB microphone, check the selected input device in the application. The
SIM7600 AT serial device is normally `/dev/ttyUSBx`; the RNDIS network interface
used for ThingsBoard may be `usb0`.

## 6. Optional Python model dependencies

Run these commands inside the activated project virtual environment.

### 6.1 BirdNET

The BirdNET model option requires the TensorFlow extra. Installing only the
base `birdnet` package is insufficient for this application:

```powershell
python -m pip install "birdnet[tf]"
```

On Raspberry Pi, install the system audio library first:

```bash
sudo apt install -y libsndfile1
python -m pip install "birdnet[tf]"
```

Verify:

```text
python -c "import birdnet; print('BirdNET import OK')"
```

BirdNET availability depends on the Python and operating-system wheels. The
application reports `birdnet is not installed` when this optional package is
missing.

### 6.2 Matt Logic EfficientNet

Install the mobile requirements, or at minimum:

```text
python -m pip install librosa tensorflow tensorflow-hub tf-keras
```

The TensorFlow package normally supplies the Lite interpreter. Install
`tflite-runtime` only when the application reports that TensorFlow Lite is not
available and a compatible wheel exists for the platform.

### 6.3 EfficientNet-Lite0 Mobile CNN/TFLite

Install:

```text
python -m pip install -r desktop/requirements-mobile.txt
```

This installs:

- `librosa` for mel-spectrogram preprocessing;
- `tensorflow` for training;
- `tensorflow-hub` for the EfficientNet-Lite0 backbone;
- `tf-keras` for TensorFlow Hub/Keras compatibility.

The backbone is downloaded from
[`tensorflow/efficientnet/lite0/feature-vector/2`](https://tfhub.dev/tensorflow/efficientnet/lite0/feature-vector/2)
during the first training run.

## 7. Create and manage labeled audio

### 7.1 Default labels

The initial labels are:

```text
Elephant, Dog, Cow, Bird, Human, Noise
```

The application creates corresponding folders under:

```text
desktop/data/dataset/
```

At least two labels with audio are required for supervised training. Keep the
classes reasonably balanced and include representative background recordings
in `Noise`.

### 7.2 Add licensed starter elephant recordings

Place legally redistributable recordings here:

```text
desktop/sample_data/Elephant/
```

Use `.wav` or `.mp3` files. On startup, the application copies files that are
not already present into:

```text
desktop/data/dataset/Elephant/
```

The public repository does not automatically download elephant recordings.
Check the license and consent for every recording before publishing samples.

### 7.3 Record or import samples

1. Start the desktop application.
2. Open the **Training** tab.
3. Select a label from **Label**, or enter a new name and press **Add**.
4. Select the microphone and audio settings.
5. Press **Record Sample** and produce the target sound during recording.
6. Repeat across different distances, backgrounds, times, and recording
   conditions.
7. Alternatively use **Import WAV/MP3 Files** or **Import Folder to Label**.
8. Use **Open Dataset Folder** to inspect the files directly.

Recommended Android-compatible settings are sample rate `48000`, window
`3.0`, and overlap `0.5`. The recording duration can be longer; the Mobile CNN
training pipeline extracts the required 3-second windows.

### 7.4 Delete samples or labels

- **Delete Selected Label Dataset** removes the selected label’s audio files but
  keeps the label entry.
- **Delete Selected Label** removes the label folder and its `labels.json`
  entry. The last remaining label cannot be deleted.

After deleting a label, retrain the model before monitoring. A previously
loaded model may still contain the deleted label until it is replaced.

## 8. Train and deploy a desktop model

In **Training → Train / Deploy Model**, choose one option:

- **Random Forest**: fastest general desktop/RPi baseline using handcrafted
  spectral features;
- **SVM-RBF**: handcrafted features and useful for smaller datasets;
- **BirdNET Embeddings + Logistic Regression**: deep BirdNET embeddings plus a
  custom classifier;
- **Matt Logic EfficientNet Retrainable (TensorFlow)**: mel-spectrogram image
  model for desktop/RPi use;
- **EfficientNet-Lite0 Mobile CNN/TFLite**: the only model that can be packaged
  for Android.

For Android:

1. Select **EfficientNet-Lite0 Mobile CNN/TFLite**.
2. Set sample rate to `48000`.
3. Set window length to `3.0` seconds.
4. Ensure every required label has enough samples.
5. Press **Train + Deploy Model**.

The desktop application creates model-specific files under
`desktop/data/models/`, including the Mobile CNN TFLite model and labels:

```text
desktop/data/models/efficientnet_lite0_mobile_model.tflite
desktop/data/models/efficientnet_lite0_mobile_labels.txt
desktop/data/models/efficientnet_lite0_mobile_latest.joblib
```

The `.joblib` package contains metadata and training information. Android uses
the `.tflite` model and labels text file, not the `.joblib` file.

The first Mobile CNN training run can take time and needs internet access for
TensorFlow Hub. If training reports a `KerasTensor cannot be used as input to a
TensorFlow function` error, update the environment and restart the desktop app:

```powershell
python -m pip install --upgrade tensorflow tensorflow-hub tf-keras
```

## 9. Local desktop/Raspberry Pi monitoring

1. Open **Real-time Monitoring**.
2. Use **Refresh trained models**.
3. Choose a model and press **Load Selected Model**, or press **Load Last
   Trained**.
4. Set **Valid confidence threshold (%)**.
5. Set **Target label** to `Elephant` for elephant-only alerts, or leave it
   blank for any confirmed label.
6. Press **Start Monitoring**.
7. Press **Stop Monitoring** before changing the model or microphone.

Predictions are smoothed over repeated windows. A single high-confidence
prediction is not necessarily a valid detection. Test the model with audio not
used for training before relying on alerts.

## 10. SIM7600 SMS on Windows/Raspberry Pi

This is separate from Android phone-SIM SMS. The desktop app sends SMS through
the SIM7600 AT serial port.

1. Connect the SIM7600 and install `pyserial`.
2. Confirm the SIM is active, unlocked, registered, and has SMS service.
3. In **Real-time Monitoring**, select `COMx` on Windows or `/dev/ttyUSBx` on
   Raspberry Pi.
4. Enter the recipient number in international format, such as `+91...`.
5. Enable SMS transmission.
6. Choose **Cyclic SMS** or **Non-cyclic on confirmed detection**.
7. Press **Send Test SMS**.
8. Only enable live monitoring after the test succeeds.

Close other serial terminals. On Raspberry Pi, ModemManager may own the AT
port. Use the application’s **Diagnose selected port** and **Reset SMS busy**
controls when appropriate.

## 11. ThingsBoard configuration

The desktop and Android apps can upload telemetry directly. The Python API is
optional.

1. Create a ThingsBoard device.
2. Copy its device access token.
3. Enable ThingsBoard upload in the relevant application.
4. Enter the host, for example `eu.thingsboard.cloud`.
5. Enter the device token.
6. Set the upload interval.
7. Press **Send Test Telemetry** where available.
8. Create dashboard widgets using telemetry keys beginning with `animal_`.

On Windows use network interface `auto`. On Raspberry Pi use `auto` for the
normal route or `usb0` when routing through a configured SIM7600 RNDIS link.
Use HTTPS for public deployments and never commit the token.

The Android app sends telemetry directly to:

```text
https://<thingsboard-host>/api/v1/<device-token>/telemetry
```

It does not need an inference API URL or API key.

## 12. Optional Python inference API

The API is for clients that intentionally use remote inference. It is not
needed by the standalone Android APK.

From the repository root, inside the activated Python environment:

```powershell
python -m pip install -r server\requirements.txt
python -m pip install -r desktop\requirements.txt
python -m server.api
```

Check it locally:

```powershell
curl http://127.0.0.1:8000/health
```

For a private Windows test session:

```powershell
$env:API_KEY = 'use-a-long-random-value'
$env:ANIMAL_MODEL = 'desktop/data/models/deployed_model.joblib'
$env:ALERT_TARGET_LABEL = 'Elephant'
python -m server.api
```

Do not expose port 8000 to the Internet without authentication, HTTPS, and a
firewall rule. The API does not automatically read `.env`; configure the
environment variables explicitly.

## 13. Android prerequisites and dependency installation

Install on the build computer:

- Flutter SDK with a Dart SDK satisfying the `android/pubspec.yaml` constraint;
- Android Studio or the Android SDK command-line tools;
- Android SDK platform/build tools and platform tools;
- a JDK supported by the installed Flutter/Android Gradle tooling;
- a USB cable and USB debugging enabled for physical-device testing.

From the repository root:

```powershell
cd android
flutter doctor -v
flutter pub get
flutter devices
flutter analyze
flutter test
```

`flutter pub get` installs all Flutter dependencies declared in
`android/pubspec.yaml`, including `tflite_flutter`, `record`, `http`,
`path_provider`, and `shared_preferences`. No separate manual installation of
the native TFLite runtime is required.

The important direct Flutter dependencies are:

```text
http: ^1.2.2
path_provider: ^2.1.4
record: 6.1.0
shared_preferences: ^2.3.2
tflite_flutter: ^0.12.1
```

The Android project also uses the Gradle/Kotlin versions defined in its
checked-in Android project files. Do not manually copy `.aar`, LiteRT, or TensorFlow
libraries into the project. Run `flutter pub get` after cloning or after
changing `pubspec.yaml`.

If `flutter doctor -v` reports a missing Android SDK, accept the licenses and
install the missing SDK components through Android Studio’s SDK Manager. If a
phone is not listed by `flutter devices`, enable Developer Options and USB
debugging, accept the phone’s authorization prompt, and install the device’s
USB driver on Windows if required.

## 14. Build the standalone Android APK

### 14.1 Prepare the model

On Windows or Raspberry Pi, train the Mobile CNN with the exact Android
settings from Section 8. The desktop build button copies these files into
`android/assets/`:

```text
efficientnet_lite0_mobile_model.tflite
efficientnet_lite0_mobile_labels.txt
```

Do not copy a `.joblib` file into Android assets. Do not use Random Forest,
SVM, BirdNET, or Matt Logic for Android.

### 14.2 Choose the SMS build mode

The desktop Training tab has two buttons:

#### Build Play-compatible APK

- omits `SEND_SMS`;
- omits the direct `SmsManager` implementation;
- opens the phone SMS composer so the user reviews and sends the message;
- is the recommended public/Play testing build.

#### Build Field APK (automatic SIM SMS)

- includes `SEND_SMS`;
- sends automatically through the phone SIM after permission is granted;
- is intended for private/off-Play field deployments.

Google Play treats SMS permissions as highly sensitive. Do not add the field
permission to a Play release unless the app qualifies under current Google Play
policy.

### 14.3 Configure release signing for the Play build

The Gradle project reads:

```text
android/android/key.properties
```

Start from:

```text
android/android/key.properties.example
```

If the application has never been published, create a new upload keystore from
PowerShell:

```powershell
cd "D:\Projects\EleAid\Codex version of EleAid\android\android"
keytool -genkeypair -v `
  -keystore eleaid-upload-key.jks `
  -alias eleaid-upload `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000
Copy-Item key.properties.example key.properties
notepad key.properties
```

If `keytool` is not on PATH, use the Android Studio JDK path, commonly:

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v `
  -keystore eleaid-upload-key.jks `
  -alias eleaid-upload `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000
```

Set the values in `key.properties` without quotes:

```properties
storePassword=the_password_you_chose
keyPassword=the_password_you_chose
keyAlias=eleaid-upload
storeFile=eleaid-upload-key.jks
```

The `.jks` file and `key.properties` are secret signing material. Never commit
or publish them. If an app has already been published, use its existing upload
key instead of generating a new one.

The desktop **Build Play-compatible APK** button checks for this signing file
before starting. This prevents accidental creation of a debug-signed public
APK.

### 14.4 Build from the desktop application

1. Start the desktop application with its Python environment active.
2. Train and deploy the Mobile CNN.
3. Open **Training**.
4. Press **Build Play-compatible APK** or **Build Field APK (automatic SIM
   SMS)**.
5. Wait for the status/log area to report success.

The button runs `flutter pub get`, copies the model and labels, and invokes a
release APK build. The generated files are:

```text
android/build/app/outputs/flutter-apk/app-play-release.apk
android/build/app/outputs/flutter-apk/app-field-release.apk
```

### 14.5 Build from PowerShell

From the repository root:

```powershell
cd android
flutter pub get
flutter build apk --flavor play --release --no-shrink --dart-define=ELEAID_DIRECT_SMS=false
```

For the private field build:

```powershell
flutter build apk --flavor field --release --no-shrink --dart-define=ELEAID_DIRECT_SMS=true
```

For Google Play submission, an Android App Bundle is normally preferred:

```powershell
flutter build appbundle --flavor play --release --no-shrink --dart-define=ELEAID_DIRECT_SMS=false
```

The desktop button currently creates APK files for direct installation. Use
the bundle command for Play Console upload when required.

## 15. Install and use the Android application

Install the generated APK on the phone. For a public test, use the Play flavor;
for a private automatic-SMS installation, use the field flavor.

On first launch:

1. Grant microphone permission.
2. Confirm the model status says the local EfficientNet-Lite0 model is ready.
3. Enter the target label, normally `Elephant`.
4. Set the confidence threshold.
5. Configure ThingsBoard host/token if telemetry is required.
6. Configure a phone number if SMS is required.
7. Press **Start**.

The Android app records continuous 3-second, 48 kHz mono windows and performs
inference locally. It does not require a host computer, inference API URL, or
API key. Keep the application open in the foreground; an always-on background
foreground service is not included yet.

In the Play flavor, confirmed detections are displayed locally and SMS messages
are composed through the phone’s messaging application for user review. In the
field flavor, Android requests SMS permission and can send confirmed alerts
automatically through the phone SIM.

### Record labelled samples on Android

The Android app can also be used as a portable data-collection tool. This does
not train a model on the phone; training remains on Windows or Raspberry Pi.

1. Open **Collect labelled training audio**.
2. Enter the label, or tap one of the quick label buttons. `Elephant` is the
   default label.
3. Set the recording duration.
4. Tap **Record labelled sample**, then **Stop and save**.
5. Repeat for every label and recording location needed.
6. Tap **Export ZIP** and share the ZIP to a computer using Drive, USB, email,
   or another file-transfer method.

Recordings stay in the app's private storage until exported. The ZIP contains
the folder layout `EleAidRecordings/<label>/<recording>.wav` and a manifest.
In the desktop app, click **Import Android Recordings ZIP**. The desktop app
will preserve the labels, create new labels when necessary, and place the WAV
files in its training dataset. Review the Dataset Summary, add more samples if
needed, and retrain the selected model.

For reliable training, collect multiple varied recordings per label, including
negative examples such as `Noise` or `Human`. Do not put a recording under the
wrong label: the Android folder name becomes the training label.

## 16. Troubleshooting

### `ModuleNotFoundError: No module named scipy` or `No module named pip`

The application was started outside the project virtual environment. From the
repository root run:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r desktop\requirements.txt
```

### PowerShell says `Activate.ps1` is not recognized

Use the exact command from the repository root:

```powershell
.\.venv\Scripts\Activate.ps1
```

If execution policy blocks it, run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### FFmpeg warning or MP3 import failure

You installed FFmpeg source code rather than a Windows binary. Download a
prebuilt package, confirm `bin\ffmpeg.exe` exists, add that `bin` directory to
PATH, reopen PowerShell and the desktop app, then verify:

```powershell
where.exe ffmpeg
ffmpeg -version
```

### `birdnet is not installed`

Activate `.venv` and install the TensorFlow extra:

```powershell
python -m pip install "birdnet[tf]"
```

Restart the desktop application after installation.

### KerasTensor error during Mobile CNN training

Update the compatible TensorFlow/Keras packages inside the active environment:

```powershell
python -m pip install --upgrade tensorflow tensorflow-hub tf-keras
```

Restart the desktop application. Do not mix a separately constructed Keras 3
symbolic input with the TensorFlow Hub layer used by this project.

### Android says model unavailable

The APK was built without the model assets. Train the Mobile CNN with 48 kHz
and 3 seconds, then use the desktop Android build button. Confirm these files
exist before building:

```text
android/assets/efficientnet_lite0_mobile_model.tflite
android/assets/efficientnet_lite0_mobile_labels.txt
```

### Play APK signing error: `eleaid-upload-key.jks not found`

Create the keystore in the same directory expected by `key.properties`:

```text
D:\Projects\EleAid\Codex version of EleAid\android\android\eleaid-upload-key.jks
```

Confirm:

```powershell
cd "D:\Projects\EleAid\Codex version of EleAid\android\android"
Test-Path .\eleaid-upload-key.jks
```

The result must be `True`. If the app was already published, do not replace its
original upload key.

### Play Protect blocks an APK

Use the Play flavor, not the field flavor. The field flavor intentionally
contains `SEND_SMS` and is not intended for Play distribution. The Play flavor
also needs a real user-owned release signing key; a debug-signed APK may still
be treated as an unknown developer. Do not permanently disable Play Protect.

### Flutter reports a `record_android` Kotlin Gradle Plugin warning

This is currently a build warning from the recorder plugin, not a failed
dependency resolution. If the build ends with `Built ...apk`, the warning did
not prevent the APK from being created. Keep the pinned `record` version in
`android/pubspec.yaml` unless you have tested a newer major version.

### No microphone on Android

Grant microphone permission in Android settings, close other recording apps,
and restart EleAid. The model expects 48 kHz audio; the app resamples a WAV if
the recorder returns another rate.

### ThingsBoard upload fails

Check the host, device token, HTTPS connectivity, and upload interval. On the
desktop Raspberry Pi application check the selected network interface. On
Android the phone needs Internet access to the ThingsBoard host.

### SIM7600 SMS port is busy

Close serial terminals, stop services using the port, verify the AT port, and
use **Diagnose selected port**. On Raspberry Pi check ModemManager.

## 17. Public-release checklist

Before publishing the repository or an APK:

1. Remove `desktop/data/`, raw audio, phone numbers, ThingsBoard tokens, API
   keys, and generated model artifacts unless you intentionally licensed them
   for publication.
2. Keep `key.properties` and `.jks` files outside Git.
3. Publish only legally redistributable sample audio and document its license.
4. Explain that acoustic detection is probabilistic and must not be the sole
   safety mechanism.
5. Use the Play flavor for Play Console and complete any required permission,
   privacy, and data-safety declarations.
6. Test the signed build on a real phone, including microphone, local
   inference, ThingsBoard, and the selected SMS behavior.
7. Test desktop monitoring separately on one Windows system and one Raspberry
   Pi before field deployment.
