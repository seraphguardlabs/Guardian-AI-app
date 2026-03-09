import 'dart:async';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/app_logger.dart';

class GemmaManager {
  static final GemmaManager instance = GemmaManager._Internal();
  GemmaManager._Internal();

  // Model ID for Gemma 3n (Stable version from mobile-ai)
  static const String modelId = 'gemma-3n-E2B-it-int4.task';
  
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

  /// Whether the model has been downloaded and is ready for activation.
  bool get modelReady => _modelReady;

  /// Whether the model has been loaded into the inference engine this session.
  bool get modelActivated => _modelActivated;

  Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;
    
    try {
      if (hfToken.isEmpty) {
        AppLogger.log('❌ GemmaManager: hfToken is empty – is .env missing? Copy .env.example to .env and add your HuggingFace token.');
        _statusController.add('Error: Missing HuggingFace token');
        return;
      }
      AppLogger.log('🤖 GemmaManager: Initializing FlutterGemma...');
      // Initialize the plugin with the HuggingFace token
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

  Future<bool> isModelInstalled() async {
    if (_modelReady) return true;
    try {
      final installed = await FlutterGemma.isModelInstalled(modelId);
      if (installed) _modelReady = true;
      return installed;
    } catch (e) {
      AppLogger.log('⚠️ GemmaManager: Error checking installation: $e');
      return false;
    }
  }

  /// Load the model into the inference engine. Must be called each session
  /// before getActiveModel() will work, even if the model files are on disk.
  Future<void> activateModel() async {
    if (_modelActivated) return;
    final url = 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/$modelId';
    AppLogger.log('🤖 GemmaManager: Activating model in inference engine...');
    await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
        .fromNetwork(url, token: hfToken)
        .install();
    _modelActivated = true;
    _modelReady = true;
    AppLogger.log('✅ GemmaManager: Model activated in inference engine.');
  }

  Future<void> downloadModel() async {
    if (_isDownloading) return;
    _isDownloading = true;
    
    try {
      _statusController.add('Downloading Model...');
      AppLogger.log('🤖 GemmaManager: Starting download from HuggingFace...');
      
      // The URL for the gemma-3n model on HuggingFace
      final url = 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/$modelId';
      
      // Use the modern installation builder
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(url, token: hfToken)
          .withProgress((progress) {
            _progressController.add(progress / 100);
            _statusController.add('Downloading: $progress%');
            if (progress % 2 == 0) AppLogger.log('📥 Download Progress: $progress%');
          })
          .install();

      _modelReady = true;
      _modelActivated = true;
      _statusController.add('Ready');
      _progressController.add(1.0);
      AppLogger.log('✅ GemmaManager: Model installed successfully.');
      
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
