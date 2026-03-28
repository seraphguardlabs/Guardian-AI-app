import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

// ───────────────────────────────────────────────────────────────────────────
// Public state enum — emitted by ModelManager.stateStream
// ───────────────────────────────────────────────────────────────────────────
enum ModelState {
  /// No model file found; user must download or pick from storage.
  notFound,

  /// Dio download in progress.
  downloading,

  /// Registering the local .task file with FlutterGemma.
  registering,

  /// Loading the registered model into the inference engine.
  loading,

  /// Model is fully loaded and inference-ready.
  ready,

  /// An unrecoverable error occurred (check [ModelManager.lastError]).
  error,
}

// ───────────────────────────────────────────────────────────────────────────
// ModelManager — singleton that owns the entire model lifecycle
// ───────────────────────────────────────────────────────────────────────────
class ModelManager {
  static final ModelManager instance = ModelManager._();
  ModelManager._();

  // ── Prefs keys ──────────────────────────────────────────────────────────
  static const _keyModelPath = 'model_file_path';
  static const _keyModelExpectedSize = 'model_expected_size';

  // ── Model constants ─────────────────────────────────────────────────────
  static const String modelFileName = 'gemma-3n-E2B-it-int4.task';
  static const String _huggingFaceUrl =
      'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/$modelFileName';

  static String get _hfToken => dotenv.env['hfToken'] ?? '';

  // ── Public state ────────────────────────────────────────────────────────
  final _stateController = StreamController<ModelState>.broadcast();
  Stream<ModelState> get stateStream => _stateController.stream;

  ModelState _currentState = ModelState.notFound;
  ModelState get currentState => _currentState;

  double _downloadProgress = 0.0;
  double get downloadProgress => _downloadProgress;

  String? _lastError;
  String? get lastError => _lastError;

  /// The ready inference model. Null until [currentState] == [ModelState.ready].
  InferenceModel? _model;
  InferenceModel? get model => _model;

  // ── Internal ────────────────────────────────────────────────────────────
  bool _disposed = false;

  void _emit(ModelState state) {
    _currentState = state;
    if (!_disposed) _stateController.add(state);
  }

  // ─────────────────────────────────────────────────────────────────────────
  /// Returns true if a valid model file is found at the persisted path.
  /// Does NOT load the model into the inference engine.
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> checkModel() async {
    AppLogger.log('[ModelManager] checkModel()');
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_keyModelPath);
    final expectedSize = prefs.getInt(_keyModelExpectedSize) ?? 0;

    if (path == null || path.isEmpty) {
      AppLogger.log('[ModelManager] No persisted model path.');
      _emit(ModelState.notFound);
      return false;
    }

    final file = File(path);
    if (!await file.exists()) {
      AppLogger.log('[ModelManager] Model file not found at $path');
      _emit(ModelState.notFound);
      return false;
    }

    final actualSize = await file.length();

    if (expectedSize > 0 && actualSize != expectedSize) {
      AppLogger.log(
        '[ModelManager] Size mismatch: actual=$actualSize expected=$expectedSize — treating as partial/corrupt.',
      );
      _emit(ModelState.notFound);
      return false;
    }

    AppLogger.log(
      '[ModelManager] Model OK at $path (${(actualSize / 1024 / 1024 / 1024).toStringAsFixed(2)} GB)',
    );
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  /// Downloads the model from HuggingFace to [destDir] using Dio.
  /// Supports resumable downloads via HTTP Range headers.
  /// Persists the final path + expected size to SharedPreferences.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> downloadModel({
    String? destDir,
    void Function(double progress, double speedMbps, Duration? eta)? onProgress,
  }) async {
    _emit(ModelState.downloading);
    _downloadProgress = 0.0;

    if (_hfToken.isEmpty) {
      _lastError = 'HuggingFace token (hfToken) is missing from .env';
      AppLogger.log('[ModelManager] ❌ $_lastError');
      _emit(ModelState.error);
      return;
    }

    // Resolve destination directory
    final dir = destDir != null
        ? Directory(destDir)
        : Directory(
            '${(await getExternalStorageDirectory())?.path ?? (await getApplicationDocumentsDirectory()).path}/guardian_ai',
          );
    if (!await dir.exists()) await dir.create(recursive: true);

    final modelFile = File('${dir.path}/$modelFileName');
    final partFile = File('${dir.path}/$modelFileName.part');

    AppLogger.log('[ModelManager] Download target: ${modelFile.path}');

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(hours: 2),
      ),
    );

    const maxRetries = 5;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      AppLogger.log('[ModelManager] Download attempt $attempt/$maxRetries');

      try {
        // ── Resolve expected size via HEAD (once per attempt) ──────────────
        int expectedSize = 0;
        try {
          final head = await dio.head<dynamic>(
            _huggingFaceUrl,
            options: Options(
              headers: {'Authorization': 'Bearer $_hfToken'},
              validateStatus: (_) => true,
            ),
          );
          final cl = head.headers.value('content-length');
          if (cl != null) {
            expectedSize = int.tryParse(cl) ?? 0;
            AppLogger.log('[ModelManager] Content-Length from server: $expectedSize bytes');

            // Persist for offline integrity checks
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt(_keyModelExpectedSize, expectedSize);
          }
        } catch (e) {
          AppLogger.log('[ModelManager] ⚠️ HEAD request failed: $e — will skip size check this run');
        }

        // ── Check if already complete ──────────────────────────────────────
        if (await modelFile.exists()) {
          final actualSize = await modelFile.length();
          if (expectedSize > 0 && actualSize == expectedSize) {
            AppLogger.log('[ModelManager] Model already complete on disk. Skipping download.');
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_keyModelPath, modelFile.path);
            _emit(ModelState.notFound); // trigger next phase (register)
            return;
          } else {
            AppLogger.log('[ModelManager] Existing model file has wrong size — deleting.');
            await modelFile.delete();
          }
        }

        // ── Resume partial download if .part file exists ───────────────────
        int downloadedBytes = 0;
        if (await partFile.exists()) {
          downloadedBytes = await partFile.length();
          AppLogger.log('[ModelManager] Resuming from $downloadedBytes bytes');
        }

        final headers = <String, dynamic>{
          'Authorization': 'Bearer $_hfToken',
          'Connection': 'keep-alive',
        };
        if (downloadedBytes > 0) {
          headers['Range'] = 'bytes=$downloadedBytes-';
        }

        final response = await dio.get<ResponseBody>(
          _huggingFaceUrl,
          options: Options(
            responseType: ResponseType.stream,
            headers: headers,
            validateStatus: (_) => true,
          ),
        );

        // If server ignored Range and returned 200, restart from 0
        if (downloadedBytes > 0 && response.statusCode == 200) {
          AppLogger.log('[ModelManager] ⚠️ Server ignored Range; restarting from 0');
          downloadedBytes = 0;
          if (await partFile.exists()) await partFile.delete();
        }

        final raf = partFile.openSync(mode: FileMode.append);
        int received = downloadedBytes;
        int lastLogPct = -1;
        bool corrupt = false;
        final startTime = DateTime.now();

        await for (final chunk in response.data!.stream) {
          raf.writeFromSync(chunk);
          received += chunk.length;

          if (expectedSize > 0) {
            final progress = received / expectedSize;
            _downloadProgress = progress;

            final elapsed = DateTime.now().difference(startTime).inMilliseconds;
            final speedMbps = elapsed > 0
                ? ((received - downloadedBytes) / 1024 / 1024) / (elapsed / 1000)
                : 0.0;
            final remaining = expectedSize - received;
            final eta = speedMbps > 0
                ? Duration(seconds: (remaining / 1024 / 1024 / speedMbps).round())
                : null;

            onProgress?.call(progress, speedMbps, eta);

            final pct = (progress * 100).toInt();
            if (pct > lastLogPct && pct % 5 == 0) {
              lastLogPct = pct;
              final diskSize = partFile.lengthSync();
              AppLogger.log('[ModelManager] $pct% | received=$received disk=$diskSize speed=${speedMbps.toStringAsFixed(1)} MB/s');
              if (diskSize != received) {
                AppLogger.log('[ModelManager] ❌ Disk/memory mismatch — corruption detected');
                corrupt = true;
                break;
              }
            }
          }
        }

        raf.closeSync();

        if (corrupt) {
          if (await partFile.exists()) await partFile.delete();
          AppLogger.log('[ModelManager] Corrupt .part deleted. Retrying...');
          continue;
        }

        // ── Final integrity check ──────────────────────────────────────────
        if (expectedSize > 0) {
          final finalSize = partFile.lengthSync();
          if (finalSize != expectedSize) {
            AppLogger.log('[ModelManager] ❌ Final size $finalSize != expected $expectedSize. Retrying...');
            if (await partFile.exists()) await partFile.delete();
            continue;
          }
        }

        // ── Rename .part → .task ───────────────────────────────────────────
        await partFile.rename(modelFile.path);
        AppLogger.log('[ModelManager] ✅ Download complete → ${modelFile.path}');

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyModelPath, modelFile.path);

        return; // success

      } on DioException catch (e) {
        AppLogger.log('[ModelManager] ❌ Dio error on attempt $attempt: ${e.message}');
        if (attempt == maxRetries) {
          _lastError = 'Download failed after $maxRetries attempts: ${e.message}';
          _emit(ModelState.error);
          return;
        }
        await Future.delayed(const Duration(seconds: 5));
      } catch (e, st) {
        AppLogger.logError('[ModelManager] Unexpected error on attempt $attempt', e, st);
        if (attempt == maxRetries) {
          _lastError = e.toString();
          _emit(ModelState.error);
          return;
        }
        await Future.delayed(const Duration(seconds: 5));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  /// Let the user pick a .task file from device storage.
  /// Saves the path to SharedPreferences (no file copy — references in place).
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> pickModelFromStorage() async {
    AppLogger.log('[ModelManager] Launching file picker...');
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || result.files.single.path == null) {
        AppLogger.log('[ModelManager] File pick cancelled.');
        return false;
      }

      final pickedPath = result.files.single.path!;
      AppLogger.log('[ModelManager] Picked: $pickedPath');

      final file = File(pickedPath);
      final size = await file.length();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyModelPath, pickedPath);
      // For user-picked files we don't have a server Content-Length,
      // so persist the actual size as the expected size for future checks.
      await prefs.setInt(_keyModelExpectedSize, size);

      AppLogger.log('[ModelManager] Persisted picked path (${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB)');
      return true;
    } catch (e, st) {
      AppLogger.logError('[ModelManager] File pick error', e, st);
      _lastError = e.toString();
      _emit(ModelState.error);
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  /// Register the model file with FlutterGemma + load it into the
  /// inference engine. Only call after [checkModel()] returns true.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> loadModel() async {
    AppLogger.log('[ModelManager] loadModel()');

    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_keyModelPath);
    if (path == null) {
      _lastError = 'No model path persisted — run checkModel() first.';
      _emit(ModelState.error);
      return;
    }

    // ── Register with FlutterGemma ─────────────────────────────────────────
    _emit(ModelState.registering);
    AppLogger.log('[ModelManager] Registering model from file: $path');
    try {
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(path)
          .install();
      AppLogger.log('[ModelManager] ✅ Model registered with FlutterGemma');
    } catch (e, st) {
      AppLogger.logError('[ModelManager] Registration failed', e, st);
      _lastError = 'Registration failed: $e';
      _emit(ModelState.error);
      return;
    }

    // ── Load into inference engine ─────────────────────────────────────────
    _emit(ModelState.loading);
    AppLogger.log('[ModelManager] Loading model into inference engine...');
    try {
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        supportImage: true,
      );
      AppLogger.log('[ModelManager] ✅ Model ready (maxTokens=${_model!.maxTokens})');
      _emit(ModelState.ready);
    } catch (e, st) {
      AppLogger.logError('[ModelManager] Load failed', e, st);
      _lastError = 'Load failed: $e';
      _model = null;
      _emit(ModelState.error);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  /// Returns the path the model will be downloaded to (for display in UI).
  // ─────────────────────────────────────────────────────────────────────────
  Future<String> getDefaultDownloadPath() async {
    final base = (await getExternalStorageDirectory())?.path ??
        (await getApplicationDocumentsDirectory()).path;
    return '$base/guardian_ai/$modelFileName';
  }

  void dispose() {
    _disposed = true;
    _stateController.close();
  }
}
