# EleAid Android standalone app

This Flutter app performs inference locally using the packaged
**EfficientNet-Lite0 Mobile CNN/TFLite** model. It does not require an
inference API URL or API key. It can publish ThingsBoard telemetry directly.

There are two Android build modes:

- **Play**: does not request `SEND_SMS`; it opens the phone SMS composer so the
  user can review and send a message. This is the default public-distribution
  mode.
- **Field**: includes `SEND_SMS` and can send automatic SMS through the phone
  SIM. Use this for private/off-Play deployments, subject to the device and
  distribution channel’s SMS policies.

The desktop app copies the trained model and labels into `android/assets/`
when an APK build is pressed. The model must be trained with 48 kHz sample
rate and a 3-second window. Android is an inference client only; model
training remains on Windows or Raspberry Pi.

For a Play release, create
`android/android/key.properties` from
`android/android/key.properties.example` and configure your own upload keystore
before building. Never publish the keystore or `key.properties`.

From this directory:

```text
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter devices
```

The Flutter dependencies are resolved from `pubspec.yaml`; do not install a
separate Android TFLite SDK. Android Studio must provide a compatible Android
SDK and JDK. For the complete Windows/Raspberry Pi installation, FFmpeg setup,
model training, signing, and troubleshooting guide, see
`../docs/USER_GUIDE.md`.

For direct command-line builds:

```text
flutter build apk --flavor play --release --no-shrink --dart-define=ELEAID_DIRECT_SMS=false
flutter build apk --flavor field --release --no-shrink --dart-define=ELEAID_DIRECT_SMS=true
```

After installing the generated APK, grant microphone permission, configure the
optional phone number/ThingsBoard token, and press Start. See
`../docs/USER_GUIDE.md` for model building and deployment guidance.

## Collect labelled training samples on Android

The app can record labelled mono WAV samples without training on the phone.
Enter a label (or tap a quick label button), choose a duration, tap **Record
labelled sample**, and then tap **Stop and save**. The default label is
`Elephant`.

Use **Export ZIP** to share all recordings. The ZIP has this layout:

```text
EleAidRecordings/
  Elephant/
    Elephant_<timestamp>.wav
  Noise/
    Noise_<timestamp>.wav
  manifest.json
```

On the desktop Training tab, choose **Import Android Recordings ZIP**. Labels
are preserved and new labels are added automatically. Then review the dataset
and train the model. Recording samples on Android does not train or modify the
model installed on the phone.
