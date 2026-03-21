import 'dart:async';
import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/app_logger.dart';

class GemmaManager {
  static final GemmaManager instance = GemmaManager._Internal();
  GemmaManager._Internal();

  // Model filename (must match what the plugin downloads from the URL)
  static const String modelId = 'gemma-3n-E2B-it-int4.task';

  // Minimum file size for a complete model (2.5GB) — used for our own FS check
  static const int _minModelSizeBytes = 2500 * 1024 * 1024; // 2.5 GB

  // Read token from .env file
  static String get hfToken => dotenv.env['hfToken'] ?? '';

  final _statusController = StreamController<String>.broadcast();
  final _progressController = StreamController<double>.broadcast();

  Stream<String> get statusStream => _statusController.stream;
  Stream<double> get progressStream => _progressController.stream;

  bool _isInitializing = false;
  bool _isInitialized = false;
  bool _isDownloading = false;
  bool _modelReady = false;
  bool _modelActivated = false;

  bool get modelReady => _modelReady;
  bool get modelActivated => _modelActivated;

  /// Directly checks if the model file exists on disk with a valid size.
  /// This is a reliable fallback when the plugin's isModelInstalled() returns
  /// a false negative after a crash/restart.
  Future<bool> _isModelFileOnDisk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      // Apply Android path correction: /data/user/0/ -> /data/data/
      final correctedPath = dir.path.contains('/data/user/0/')
          ? dir.path.replaceFirst('/data/user/0/', '/data/data/')
          : dir.path;
      final filePath = '$correctedPath/$modelId';
      final file = File(filePath);

      if (!await file.exists()) {
        AppLogger.log('🔍 GemmaManager: File not at $filePath');
        return false;
      }

      final fileSize = await file.length();
      AppLogger.log('🔍 GemmaManager: Model file found at $filePath (${(fileSize / 1024 / 1024 / 1024).toStringAsFixed(2)} GB)');

      if (fileSize < _minModelSizeBytes) {
        AppLogger.log('⚠️ GemmaManager: File exists but too small (${fileSize} bytes) — likely partial/corrupt.');
        return false;
      }
      return true;
    } catch (e) {
      AppLogger.log('⚠️ GemmaManager: Error checking file on disk: $e');
      return false;
    }
  }

  Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;

    try {
      if (hfToken.isEmpty) {
        final errorMsg = '❌ GemmaManager: hfToken is empty. Ensure .env exists with hfToken=...';
        AppLogger.log(errorMsg);
        _statusController.add('Error: $errorMsg');
        return;
      }
      AppLogger.log('🤖 GemmaManager: Initializing FlutterGemma...');
      await FlutterGemma.initialize(huggingFaceToken: hfToken);
      _isInitialized = true;

      final installed = await isModelInstalled();
      if (installed) {
        AppLogger.log('✅ GemmaManager: Model already installed.');
        _modelReady = true;
        _statusController.add('Ready');
      } else {
        AppLogger.log('⚠️ GemmaManager: Model not found. User needs to download.');
        _statusController.add('Not Installed');
      }
    } catch (e) {
      AppLogger.log('❌ GemmaManager: Initialization error: $e');
      _statusController.add('Error: $e');
    } finally {
      _isInitializing = false;
    }
  }

  /// Two-stage check: plugin API first, then raw file-system check as fallback.
  /// This prevents false negatives after app crashes.
  Future<bool> isModelInstalled() async {
    if (_modelReady) return true;

    // Stage 1: Ask the plugin
    try {
      final pluginSays = await FlutterGemma.isModelInstalled(modelId);
      if (pluginSays) {
        _modelReady = true;
        AppLogger.log('✅ GemmaManager: Plugin confirms model is installed.');
        return true;
      }
    } catch (e) {
      AppLogger.log('⚠️ GemmaManager: Plugin check failed: $e');
    }

    // Stage 2: Fallback — directly check the filesystem
    final fileOnDisk = await _isModelFileOnDisk();
    if (fileOnDisk) {
      _modelReady = true;
      AppLogger.log('✅ GemmaManager: File-system check confirms model is on disk. Plugin had a false negative.');
      return true;
    }

    return false;
  }

  /// Activate the model in the inference engine for the current session.
  Future<void> activateModel() async {
    if (_modelActivated) return;

    // Always do a fresh isModelInstalled() check to catch file-system truth
    final installed = await isModelInstalled();
    if (!installed) {
      AppLogger.log('🤖 GemmaManager: Model not on disk, triggering download via activateModel...');
      final url = 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/$modelId';
      try {
        await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
            .fromNetwork(url, token: hfToken, foreground: true)
            .install();
        _modelActivated = true;
        _modelReady = true;
        AppLogger.log('✅ GemmaManager: Model activated in inference engine.');
        return;
      } catch (e) {
        AppLogger.log('❌ GemmaManager: Activation error: $e');
        rethrow;
      }
    }

    // Model is on disk but not yet loaded into inference engine
    // We need to call installModel().fromFile().install() to load the already-downloaded model
    AppLogger.log('🤖 GemmaManager: Model on disk. Loading into inference engine...');
    try {
      // Get the actual file path where the model is stored
      final dir = await getApplicationDocumentsDirectory();
      final correctedPath = dir.path.contains('/data/user/0/')
          ? dir.path.replaceFirst('/data/user/0/', '/data/data/')
          : dir.path;
      final modelFilePath = '$correctedPath/$modelId';
      
      AppLogger.log('📁 GemmaManager: Loading from disk: $modelFilePath');

      // Call installModel().fromFile().install() with the actual file path
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(modelFilePath)
          .install();
      _modelActivated = true;
      _modelReady = true;
      AppLogger.log('✅ GemmaManager: Model successfully loaded into inference engine.');
    } catch (e) {
      AppLogger.log('❌ GemmaManager: Failed to load model into inference engine: $e');
      _modelActivated = false;
      rethrow;
    }
  }

  Future<void> downloadModel() async {
    if (_isDownloading) return;
    _isDownloading = true;

    try {
      _statusController.add('Checking model...');

      // Guard: if the model is already fully on disk, don't re-download
      final installed = await isModelInstalled();
      if (installed) {
        AppLogger.log('✅ GemmaManager: Model already on disk. Skipping download.');
        _modelReady = true;
        _modelActivated = true;
        _statusController.add('Ready');
        _progressController.add(1.0);
        return;
      }

      _statusController.add('Downloading Model...');
      AppLogger.log('🤖 GemmaManager: Starting download with foreground service (prevents OS kill)...');

      final url = 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/$modelId';

      // CRITICAL: foreground:true ensures Android's foreground service is used for
      // this large download. Without it, Android kills the process mid-download
      // when the app is backgrounded or the screen turns off -> partial files -> restart loop.
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(url, token: hfToken, foreground: true)
          .withProgress((progress) {
            _progressController.add(progress / 100);
            _statusController.add('Downloading: $progress%');
            if (progress % 10 == 0) AppLogger.log('📥 Download Progress: $progress%');
          })
          .install();

      _modelReady = true;
      _modelActivated = true;
      _statusController.add('Ready');
      _progressController.add(1.0);
      AppLogger.log('✅ GemmaManager: Model downloaded and installed successfully.');
    } catch (e) {
      AppLogger.log('❌ GemmaManager: Download error: $e');
      _statusController.add('Download Failed: $e');
      _progressController.add(0.0);
      rethrow;
    } finally {
      _isDownloading = false;
    }
  }

  void dispose() {
    _statusController.close();
    _progressController.close();
  }
}
