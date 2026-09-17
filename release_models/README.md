# Models for the public release package

Place validated, distributable model files here before building the release package:

```text
release_models/
├── desktop/   # desktop/Raspberry Pi Joblib model packages and metadata
├── android/   # Android TFLite model, labels, and metadata
└── samples/   # optional redistributable example WAV files
```

Do not place passwords, keystores, API keys, ThingsBoard tokens, or private
recordings in this directory.

For a desktop/Raspberry Pi model, provide the complete `.joblib` package saved
by the application. For Android, provide the `.tflite` file, its labels file,
and the preprocessing/configuration metadata used during training.

The current Track 1 package is built from the files in `desktop/` and uses the
default `Elephant` and `Noise` model classes. Review every model’s accuracy,
license, and training-data permissions before publishing it. FFmpeg binaries
must retain the license/notice supplied by their distributor; the installer
builder copies them into the package but does not change their license.
