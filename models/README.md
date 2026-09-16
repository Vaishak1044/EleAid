# Model artifacts

Trained artifacts are generated locally by the desktop application under `desktop/data/models/`.

The default label set includes `Elephant`. Put licensed starter recordings in
`desktop/sample_data/Elephant/`; the application copies them into the runtime
dataset at `desktop/data/dataset/Elephant/` on startup. Supported files are
WAV and MP3.

Do not commit them by default because they may be large, contain field data, and can expose labels or recording metadata. To publish a model, export it separately and document:

- model type and training date;
- labels and number of samples per label;
- sample rate, window length, overlap, and filter band;
- validation accuracy and confusion matrix;
- licensing/consent for every audio source.

For Android deployment, train **EfficientNet-Lite0 Mobile CNN/TFLite** in the
desktop app. Its generated artifacts are:

- `desktop/data/models/efficientnet_lite0_mobile_model.tflite`
- `desktop/data/models/efficientnet_lite0_mobile_labels.txt`
- `desktop/data/models/efficientnet_lite0_mobile_latest.joblib`

Android supports only this model. The desktop **Build Play-compatible APK** or
**Build Field APK** action copies these files into `android/assets/` so the
generated APK performs local inference without the host API.
