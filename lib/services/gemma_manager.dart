import 'dart:async';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/foundation.dart';

class GemmaManager {
  static final GemmaManager instance = GemmaManager._Internal();
  GemmaManager._Internal();

  // Model ID for Gemma 2B IT (standard for this plugin version)
  static const String modelId = 'gemma-2b-it-cpu-int4.bin';
  static const String hfToken = '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';

  final _statusController = StreamController<String>.broadcast();
  final _progressController = StreamController<double>.broadcast();

  Stream<String> get statusStream => _statusController.stream;
  Stream<double> get progressStream => _progressController.stream;

  bool _isInitializing = false;
  bool _isDownloading = false;

  Future<void> initialize() async {
    if (_isInitializing) return;
    _isInitializing = true;
    
    try {
      debugPrint('🤖 GemmaManager: Initializing FlutterGemma...');
      // Initialize the plugin with the HuggingFace token
      await FlutterGemma.initialize(huggingFaceToken: hfToken);
      
      final installed = await isModelInstalled();
      if (installed) {
        debugPrint('✅ GemmaManager: Model already installed.');
        _statusController.add('Ready');
      } else {
        debugPrint('⚠️ GemmaManager: Model not found. User needs to download.');
        _statusController.add('Not Installed');
      }
    } catch (e) {
      debugPrint('❌ GemmaManager: Initialization error: $e');
      _statusController.add('Error: $e');
    } finally {
      _isInitializing = false;
    }
  }

  Future<bool> isModelInstalled() async {
    try {
      return await FlutterGemma.isModelInstalled(modelId);
    } catch (e) {
      debugPrint('⚠️ GemmaManager: Error checking installation: $e');
      return false;
    }
  }

  Future<void> downloadModel() async {
    if (_isDownloading) return;
    _isDownloading = true;
    
    try {
      _statusController.add('Downloading Model...');
      debugPrint('🤖 GemmaManager: Starting download from HuggingFace...');
      
      // The URL for the model on HuggingFace
      final url = 'https://huggingface.co/google/gemma-2b-it-cpu-int4/resolve/main/$modelId';
      
      // Use the modern installation builder
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(url, token: hfToken)
          .withProgress((progress) {
            _progressController.add(progress / 100);
            _statusController.add('Downloading: $progress%');
            debugPrint('📥 Download Progress: $progress%');
          })
          .install();

      _statusController.add('Ready');
      _progressController.add(1.0);
      debugPrint('✅ GemmaManager: Model installed successfully.');
      
    } catch (e) {
      debugPrint('❌ GemmaManager: Download error: $e');
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
