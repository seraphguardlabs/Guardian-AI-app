# Deployment Notes - Guardian AI App
**Date:** January 27, 2026

## 1. New Features Implemented

### Conditional Screenshot Deletion & Text Threat Detection
We have enhanced the privacy and threat detection capabilities of the `ScreenMonitoringService`.

*   **OCR Integration:**
    *   Added `google_mlkit_text_recognition` dependency.
    *   Created `OCRService` (`lib/services/ocr_service.dart`) to extract text from captured screenshots.

*   **Enhanced Threat Analysis:**
    *   The system now performs **dual analysis** on every screenshot:
        1.  **Visual:** detecting explicit/violent images.
        2.  **Textual:** detecting predatory/grooming text patterns using `TextThreatDetectionService`.

*   **Privacy-First "Conditional Deletion":**
    *   A **Total Risk Score** is calculated (`max(visualScore, textScore)`).
    *   **IF Risk < Config.threshold (30%):** The screenshot is **immediately deleted** from the device storage. This saves extensive storage space and protects the child's privacy for safe activities.
    *   **IF Risk >= Config.threshold:** The screenshot is retained, and an encrypted alert (including the suspicious text) is sent to the parent.

*   **Code Refactoring:**
    *   Renamed `Config` class reference to `AppConfig` (in `task.md` planning) or fixed imports to avoid conflicts.
    *   Updated `screen_monitoring_service.dart` to integrate all components.

## 2. Current Build Status & Known Issues

**Status:** Build Failing ❌

The Android build (`flutter build apk`) is currently failing due to environment configuration issues on the local machine, NOT code errors.

### Issue A: Network / Firewall Blocking Dependencies
*   **Error:** `No route to host: getsockopt` / `No such host is known (dl.google.com)`
*   **Cause:** The Gradle build process cannot reach Google's servers to download required Android libraries (AGP 7.4.2, etc.).
*   **Fix:** Ensure stable internet connection and check firewall/VPN settings allowing Java/Gradle to access the internet.

### Issue B: Missing Android SDK Component
*   **Error:** `cmdline-tools component is missing` (reported by `flutter doctor`).
*   **Cause:** The Android SDK installation is incomplete.
*   **Fix:** Open Android Studio -> SDK Manager -> SDK Tools -> Check and install "Android SDK Command-line Tools (latest)".

## 3. Deployment Instructions

1.  **Fix Environment:** Resolve the network and SDK tool issues listed above.
2.  **Clean Build:** Run `flutter clean` and `flutter pub get`.
3.  **Build:** Run `flutter build apk --debug`.
4.  **Install:** Run `flutter run` with the Android device connected.

## 4. Git Model Policy
*   **Tracked:** `vision_mobile.onnx.data` (Small, <10MB).
*   **Ignored:** `bert_predatory.onnx.data` (267MB) - This file remains in `.gitignore` as it exceeds GitHub's strict 100MB file size limit. It cannot be pushed without setting up Git LFS.
