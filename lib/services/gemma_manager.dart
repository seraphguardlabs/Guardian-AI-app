import 'dart:async';
import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../utils/app_logger.dart';

class GemmaManager {
  static final GemmaManager instance = GemmaManager._Internal();
  GemmaManager._Internal();

  // Model ID for Gemma 3n (Stable version)
  static const String modelId = 'gemma-3n-E2B-it-int4.task';

  // Read token from .env file
  static String get hfToken => dotenv.env['HF_TOKEN'] ?? '';

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
      AppLogger.log('🤖 GemmaManager: Initializing FlutterGemma...');
      // Initialize the plugin with the HuggingFace token
      await FlutterGemma.initialize(huggingFaceToken: hfToken);

      final installed = await isModelInstalled();
      if (installed) {
        AppLogger.log('✅ GemmaManager: Model already installed.');
        _statusController.add('Ready');
      } else {
        AppLogger.log('⚠️ GemmaManager: Model not found.');
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
    try {
      return await FlutterGemma.isModelInstalled(modelId);
    } catch (e) {
      AppLogger.log('⚠️ GemmaManager: Error checking installation: $e');
      return false;
    }
  }

  Future<void> downloadModel() async {
    if (_isDownloading) return;
    _isDownloading = true;

    try {
      _statusController.add('Initializing Download...');
      AppLogger.log('🤖 GemmaManager: Starting robust download...');

      final appDocDir = await getApplicationDocumentsDirectory();
      final modelFile = File('${appDocDir.path}/$modelId');
      final partFile = File('${appDocDir.path}/$modelId.part');

      // The URL for the gemma-3n model on HuggingFace
      final url = 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/$modelId';
      
      final dio = Dio();
      const maxRetries = 3;
      bool downloadSuccess = false;

      for (int attempt = 1; attempt <= maxRetries && !downloadSuccess; attempt++) {
        try {
          if (attempt > 1) {
            AppLogger.log('🔄 GemmaManager: Retry Attempt $attempt/$maxRetries');
            _statusController.add('Retrying... ($attempt/$maxRetries)');
          }

          // Check remote size for integrity
          final headRes = await dio.head(url, options: Options(headers: hfToken.isNotEmpty ? {'Authorization': 'Bearer $hfToken'} : {}));
          final expectedSize = int.tryParse(headRes.headers.value('content-length') ?? '0') ?? 0;
          
          if (expectedSize == 0) throw Exception('Could not determine model size');

          if (!modelFile.existsSync() || modelFile.lengthSync() != expectedSize) {
            int startByte = partFile.existsSync() ? partFile.lengthSync() : 0;
            
            // If part file is too large or corrupted, reset it
            if (startByte >= expectedSize) {
              startByte = 0;
              if (partFile.existsSync()) partFile.deleteSync();
            }

            AppLogger.log('📥 GemmaManager: Downloading from $startByte / $expectedSize bytes');

            await dio.download(
              url,
              partFile.path,
              options: Options(
                headers: {
                  if (hfToken.isNotEmpty) 'Authorization': 'Bearer $hfToken',
                  if (startByte > 0) 'Range': 'bytes=$startByte-',
                },
                responseType: ResponseType.stream,
              ),
              onReceiveProgress: (count, total) {
                final currentTotal = startByte + count;
                final progress = currentTotal / expectedSize;
                _progressController.add(progress);
                _statusController.add('Downloading: ${(progress * 100).toStringAsFixed(1)}%');
              },
              deleteOnError: false,
            );

            // Verify final size
            if (partFile.lengthSync() == expectedSize) {
              if (modelFile.existsSync()) modelFile.deleteSync();
              partFile.renameSync(modelFile.path);
              downloadSuccess = true;
            }
          } else {
            downloadSuccess = true;
          }
        } catch (e) {
          AppLogger.log('⚠️ GemmaManager: Download error on attempt $attempt: $e');
          if (attempt == maxRetries) rethrow;
          await Future.delayed(const Duration(seconds: 5));
        }
      }

      _statusController.add('Installing Model...');
      AppLogger.log('🤖 GemmaManager: Registering model with FlutterGemma...');

      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
      ).fromFile(modelFile.path).install();

      _statusController.add('Ready');
      _progressController.add(1.0);
      AppLogger.log('✅ GemmaManager: Model installed successfully.');
    } catch (e) {
      AppLogger.log('❌ GemmaManager: Download failed: $e');
      _statusController.add('Download Failed: $e');
      _progressController.add(0.0);
    } finally {
      _isDownloading = false;
    }
  }

  Future<void> installModelFromFile(String path) async {
    if (_isDownloading) return;
    _isDownloading = true;

    try {
      _statusController.add('Installing Model...');
      AppLogger.log('🤖 GemmaManager: Installing from local file: $path');

      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
      ).fromFile(path).install();

      _statusController.add('Ready');
      _progressController.add(1.0);
      AppLogger.log('✅ GemmaManager: Model installed from local file.');
    } catch (e) {
      AppLogger.log('❌ GemmaManager: File installation error: $e');
      _statusController.add('Installation Failed: $e');
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

