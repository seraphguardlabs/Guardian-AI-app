# Guardian AI (Integra Branch)

## Complete AI Integration & Monitoring System

This branch contains the finalized integration of the on-device AI safety features, background monitoring, and persistent logging using the **Gemma 3** architecture.

### ✨ Key Features

#### 1. On-Device AI Safety (Gemma 3)
- Fully integrated with `flutter_gemma` (0.12.5).
- Automatically downloads and loads the **Google Gemma 3n** model (`gemma-3n-E2B-it-int4.task`) direct from Hugging Face.
- Secured API Token access via `.env` files.
- Zero latency initialization for real-time monitoring.

#### 2. Background Screen Monitoring
- Enforces a Strict **5-Second Adaptive Cycle**. Every 5 seconds, it captures the screen, runs it through the Gemma 3 model, determines a risk score (0-100), and actively monitors for cyberbullying, explicit content, or depression.
- **Zero-Cache Architecture**: The screenshot `File` is deleted immediately after the AI analyzes it, maintaining strict user privacy and preventing storage bloat.
- Fully compatible with Android 14 Foreground Service requirements.

#### 3. Extensive Application Logging (`AppLogger`)
- **Cross-Isolate Sync**: Background isolates and the main UI thread all safely write real-time logs to a persistent file (`ai_guardian.log`).
- **Global Crash Handling**: Wraps the root app in `runZonedGuarded` to prevent silent force closes, capturing stack traces instantly.
- **Log Viewer UI**: The Child Profile screen features a hidden Bug/Debug Icon (🐞). Tapping it opens an internal UI to read, refresh, and clear the system logs in real time.

### 🛠️ Fixed Issues
- **Resolved**: App freezing/force-closing after permissions were granted.
- **Resolved**: Model 404 download errors (Fixed by utilizing the correct Google Gemma 3 repository).
- **Resolved**: UI Model Download button doing nothing.
- **Resolved**: Background isolate failing to invoke the UI logger (Migrated to persistent file storage).

### 🚀 Getting Started
1. Clone the repository and checkout the `integra` branch.
2. In the root `guardian_ai` folder, create a `.env` file containing your Hugging Face API key:
   ```env
   hfToken=your_hf_token_here
   ```
3. Run `flutter clean` and `flutter pub get`.
4. Run `flutter build apk --release` or launch onto a physical device. Note: Background testing relies on the Android Accessibility and Projection services, making an Emulator unsuitable for deep testing.
