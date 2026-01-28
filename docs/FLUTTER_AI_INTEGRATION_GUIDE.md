# Guardian AI Flutter Integration Guide

This guide details how the AI models (LSTM, BERT, Vision) have been integrated into the `Guardian-AI-app` project.

## 1. Project Structure

The extracted model files have been placed in the `assets/models/` directory:
- `assets/models/behavior_lstm_mobile.ptl`
- `assets/models/bert_predatory.onnx`
- `assets/models/bert_predatory.onnx.data`
- `assets/models/vision_mobile.ptl`
- `assets/models/vocab.txt`

Services for interacting with these models are located in `lib/services/`:
- `behavior_model_service.dart`: Handles LSTM behavior anomaly detection.
- `text_analysis_service.dart`: Handles BERT text threat analysis.
- `vision_analysis_service.dart`: Handles image content analysis.
- `bert_tokenizer.dart`: Helper for text tokenization.

A test screen is available at:
- `lib/screens/ai_test_screen.dart`

## 2. Updated Configuration

### `pubspec.yaml`
Dependencies added:
- `pytorch_mobile`
- `onnxruntime`
- `image`

Assets registered:
- `assets/models/`

### `android/app/build.gradle.kts`
- `minSdk` set to **24** (Android 7.0).
- `ndk.abiFilters` configured for `armeabi-v7a`, `arm64-v8a`, and `x86_64`.

## 3. How to Build & Run

1.  **Clean and Get Dependencies**:
    ```bash
    flutter clean
    flutter pub get
    ```

2.  **Run the App**:
    Connect an Android device or emulator.
    ```bash
    flutter run
    ```
    *Note: The first build might take longer as it processes the model assets.*

3.  **Test the Integration**:
    Navigate to the `AiTestScreen` (you may need to temporarily set it as `home` in `main.dart` or add a navigation button to access it).
    - Tap **Test AI Models**.
    - Verify that "LSTM Anomaly" and "BERT Threat" scores are displayed.

## 4. Troubleshooting

- **"Model not found"**: Ensure `flutter pub get` was run and `assets` section in `pubspec.yaml` is correct (already configured).
- **"Out of memory"**: Test on a physical device if the emulator crashes. BERT models are memory-intensive (~300MB RAM).
- **Build Failures**: Check that your Java version matches the project requirement (Java 21).

## 5. Deployment

When building the final APK:
```bash
flutter build apk --release
```
The resulting APK will be larger (~300MB) due to the embedded AI models. This is expected for offline, on-device inference capabilities.
