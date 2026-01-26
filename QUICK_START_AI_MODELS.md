# Quick Start - AI Model Loading

## 🚀 Running the App

```bash
cd frontend_integrated
flutter clean
flutter pub get
flutter run
```

## 🧪 Testing Model Loading

### Access the AI Test Screen:
1. After app launches, navigate to `/ai_test` route
2. Click **"Initialize Models"** button
3. Watch the logs showing model loading progress

### Expected Output:
```
✅ TextAnalysisService initialization SUCCESSFUL!
  ✅ App directory: /data/user/0/com.example.guardian/documents/models
  ✅ Models directory already exists
  ✅ bert_predatory.onnx copied (769631 bytes)
  ✅ bert_predatory.onnx.data verified (267827200 bytes)
  ✅ All model files verified successfully!
```

## 🔍 Test Text Analysis

1. Models must be initialized first
2. Enter text in the test field
3. Click **"Analyze Text"**
4. View risk level:
   - 🟢 **Low Risk** (0-33%)
   - 🟡 **Medium Risk** (34-66%)
   - 🔴 **High Risk** (67-100%)

## 📊 Model Files Status

| File | Size | Status |
|------|------|--------|
| bert_predatory.onnx | 769 KB | ✅ |
| bert_predatory.onnx.data | 268 MB | ✅ |
| behavior_lstm_mobile.ptl | 571 KB | ✅ |
| vision_mobile.onnx | 261 KB | ✅ |
| vision_mobile.onnx.data | 8.9 MB | ✅ |
| vision_mobile.ptl | 8.8 MB | ✅ |
| vocab.txt | 262 KB | ✅ |

## ⚙️ Configuration

### Dependencies Added:
- `file: ^7.0.0` - File operations
- `path: ^1.8.3` - Path handling
- `path_provider: ^2.1.0` - App directory access

### Model Assets:
All files declared in `pubspec.yaml` under `flutter.assets`

### Initialization:
Models load automatically in `main.dart` when app starts

## 🐛 Troubleshooting

### Models Not Loading?
1. Run `flutter clean`
2. Delete `build/` directory
3. Run `flutter pub get`
4. Rebuild app

### Check Console Output:
Look for:
```
🤖 Initializing TextAnalysisService (AI Models)...
✅ TextAnalysisService initialized successfully
```

### Use AI Test Screen:
- Navigate to `/ai_test` route
- Click "Initialize Models"
- Check real-time logs for errors

## 📚 Files Modified

| File | Changes |
|------|---------|
| `pubspec.yaml` | Added dependencies + assets |
| `lib/main.dart` | Added initialization + route |
| `lib/services/text_analysis_service.dart` | NEW - Model loading service |
| `lib/screens/ai_test_screen.dart` | NEW - Test screen |
| `assets/models/*` | NEW - All model files |

## 🔗 Documentation

- **Detailed Fixes**: See `AI_MODEL_LOADING_FIXES.md`
- **Verification Results**: See `MODEL_LOADING_VERIFICATION.md`
- **Code Reference**: See `text_analysis_service.dart` & `ai_test_screen.dart`

## ✅ Everything is Ready!

The app is configured and ready for:
- ✅ Model loading and verification
- ✅ Text analysis (mock implementation)
- ✅ Real model integration (with ONNX Runtime package)
- ✅ Debugging via AI Test Screen

## 🎯 Next Steps

1. **Test the app** - Run and navigate to `/ai_test`
2. **Initialize models** - Click the initialization button
3. **Check logs** - Verify all models load successfully
4. **Test analysis** - Enter text and analyze
5. **Integrate real models** - Replace mock with actual ONNX/PyTorch inference

---

**Questions?** Check the detailed documentation files or run the AI Test Screen for live debugging.
