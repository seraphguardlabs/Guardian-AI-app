# Guardian AI Gemma-4-E2B-it Prototype

Flutter + Android prototype for screenshot-only child safety monitoring.

## What this prototype does

- Captures screenshots periodically with an Android `AccessibilityService`.
- Does not do screen recording.
- Runs while app UI is closed, as long as accessibility service is enabled.
- Stores safety snapshots (sexual, violence, predatory text, overall) in local storage.
- Downloads the model file once and reuses it from device storage on future runs.
- Supports first-run setup directly on device inside the APK (model URL, file name, HF token).
- Can auto-start download, model load, and monitoring after configuration is saved.

## Important status

- The screenshot loop and local model caching are implemented.
- The current native scorer is a placeholder and is not true Gemma inference yet.
- Replace `GemmaLiteEngine.score(...)` with real Gemma-4-E2B-it inference logic.

## Run

1. Install APK on Android and open the app.

2. In first-run setup card, fill:

	- Model URL
	- Model file name
	- HF token (for gated model)
	- Keep "Auto start after app opens" enabled

3. Tap Save and Start.

4. Android will ask you to enable Accessibility service once.

	After this permission is enabled, the app auto-downloads the model, loads it, and starts screenshot monitoring.
	On next launches, it reuses the downloaded model from device storage.

5. Optional developer run command (if you still run from local Flutter tooling):

	PowerShell:

	`$env:HF_TOKEN="your_hf_read_token"`
	`flutter run --dart-define=GEMMA4_MODEL_URL=https://huggingface.co/.../resolve/main/gemma-4-e2b-it.model --dart-define=GEMMA4_MODEL_FILE=gemma-4-e2b-it.model --dart-define=GEMMA4_HF_TOKEN=$env:HF_TOKEN`

	Optional model metadata overrides:

	`--dart-define=GEMMA4_MODEL_NAME=Gemma-4-E2B-it --dart-define=GEMMA4_MODEL_ID=gemma-4-e2b-it`

	If your Hugging Face URL is gated, the app sends `Authorization: Bearer <GEMMA4_HF_TOKEN>` during download.
	Keep your token out of source control.

## Key files

- Flutter UI and controls: `lib/main.dart`
- Model download caching: `lib/services/model_repository.dart`
- Flutter-native bridge: `lib/services/guardian_platform.dart`
- Android method channel: `android/app/src/main/kotlin/com/example/guardian_ai_gemma4/MainActivity.kt`
- Background screenshot service: `android/app/src/main/kotlin/com/example/guardian_ai_gemma4/GuardianAccessibilityService.kt`
- Native scoring entrypoint: `android/app/src/main/kotlin/com/example/guardian_ai_gemma4/GemmaLiteEngine.kt`
- Risk persistence: `android/app/src/main/kotlin/com/example/guardian_ai_gemma4/RiskStore.kt`

## Platform notes

- Android only in this prototype.
- `minSdk` is set to 30 because `AccessibilityService.takeScreenshot(...)` requires Android 11+.
- If user force-stops the app, Android may stop background behavior until app is opened again.

## Transformers Gemma Scorer

If you want to run Gemma with the exact Transformers pattern:

`processor = AutoProcessor.from_pretrained("google/gemma-4-E2B-it")`

`model = AutoModelForImageTextToText.from_pretrained("google/gemma-4-E2B-it")`

Use the included scorer script:

1. Install Python dependencies:

	`python -m pip install -r inference/requirements.txt`

2. Set your Hugging Face token in PowerShell:

	`$env:HF_TOKEN="your_hf_read_token"`

3. Score a screenshot:

	`python inference/gemma_guardian_scorer.py --image C:/path/to/screenshot.png --pretty`

The script outputs JSON with `sexual_content`, `violence`, `predatory_text`, and `overall_risk`.
