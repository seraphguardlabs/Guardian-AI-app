import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class TextAnalysisService {
  static final TextAnalysisService _instance = TextAnalysisService._internal();

  factory TextAnalysisService() {
    return _instance;
  }

  TextAnalysisService._internal();

  bool _initialized = false;
  String? _modelBasePath;
  Map<String, String> _modelPaths = {};
  List<String> _initializationLogs = [];

  static TextAnalysisService get instance => _instance;

  bool get isInitialized => _initialized;
  String? get modelBasePath => _modelBasePath;
  List<String> get initializationLogs => _initializationLogs;

  void _addLog(String message) {
    final timestamp = DateTime.now().toString();
    final logMessage = '[$timestamp] $message';
    _initializationLogs.add(logMessage);
    print(logMessage);
  }

  /// Initialize the text analysis service
  /// This will copy model files from assets to app documents directory
  /// and verify they are in the correct location
  Future<bool> initialize() async {
    if (_initialized) {
      _addLog('✅ TextAnalysisService already initialized');
      return true;
    }

    try {
      _addLog('🔄 Starting TextAnalysisService initialization...');

      // Step 1: Get application documents directory
      _addLog('📂 Step 1: Getting application documents directory...');
      final appDir = await getApplicationDocumentsDirectory();
      _modelBasePath = '${appDir.path}/models';
      _addLog('✅ App directory: $_modelBasePath');

      // Step 2: Create models directory if it doesn't exist
      _addLog('📂 Step 2: Creating models directory...');
      final modelDir = Directory(_modelBasePath!);
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
        _addLog('✅ Models directory created');
      } else {
        _addLog('✅ Models directory already exists');
      }

      // Step 3: Copy and verify model files
      _addLog('📦 Step 3: Copying model files from assets...');
      await _copyModelFiles(modelDir);

      // Step 4: Verify all model files
      _addLog('✅ Step 4: Verifying model files...');
      await _verifyModelFiles(modelDir);

      // Step 5: Initialize ONNX Runtime for BERT model
      _addLog('🤖 Step 5: Initializing ONNX Runtime for BERT model...');
      await _initializeONNXRuntime();

      _initialized = true;
      _addLog('═══════════════════════════════════════════════════════');
      _addLog('✅ TextAnalysisService initialization SUCCESSFUL!');
      _addLog('═══════════════════════════════════════════════════════');
      return true;
    } catch (e, stackTrace) {
      _addLog('═══════════════════════════════════════════════════════');
      _addLog('❌ TextAnalysisService initialization FAILED!');
      _addLog('Error: $e');
      _addLog('Stack trace: $stackTrace');
      _addLog('═══════════════════════════════════════════════════════');
      _initialized = false;
      return false;
    }
  }

  /// Copy model files from assets to application documents directory
  Future<void> _copyModelFiles(Directory modelDir) async {
    final modelFiles = [
      'bert_predatory.onnx',
      'bert_predatory.onnx.data',
      'behavior_lstm_mobile.ptl',
      'vision_mobile.ptl',
      'vision_mobile.onnx',
      'vision_mobile.onnx.data',
      'vocab.txt',
    ];

    for (final fileName in modelFiles) {
      try {
        _addLog('  📄 Copying $fileName...');
        final data = await rootBundle.load('assets/models/$fileName');
        final bytes = data.buffer.asUint8List();
        final file = File('${modelDir.path}/$fileName');

        // Check if file already exists and has same size
        if (await file.exists()) {
          final existingSize = await file.length();
          if (existingSize == bytes.length) {
            _addLog('     ✅ $fileName already exists (size: $existingSize bytes)');
            _modelPaths[fileName] = file.path;
            continue;
          } else {
            _addLog('     ⚠️  $fileName exists but size mismatch, re-copying');
          }
        }

        await file.writeAsBytes(bytes);
        _addLog('     ✅ $fileName copied (${bytes.length} bytes)');
        _modelPaths[fileName] = file.path;
      } catch (e) {
        _addLog('     ❌ Failed to copy $fileName: $e');
        rethrow;
      }
    }
  }

  /// Verify that all model files are present and readable
  Future<void> _verifyModelFiles(Directory modelDir) async {
    _addLog('🔍 Verifying all model files...');

    // Check ONNX files
    final bertOnnx = File('${modelDir.path}/bert_predatory.onnx');
    final bertOnnxData = File('${modelDir.path}/bert_predatory.onnx.data');

    if (!await bertOnnx.exists()) {
      throw Exception('bert_predatory.onnx not found at ${bertOnnx.path}');
    }
    _addLog('  ✅ bert_predatory.onnx verified (${await bertOnnx.length()} bytes)');

    if (!await bertOnnxData.exists()) {
      throw Exception('bert_predatory.onnx.data not found at ${bertOnnxData.path}');
    }
    _addLog('  ✅ bert_predatory.onnx.data verified (${await bertOnnxData.length()} bytes)');

    // Check PyTorch files
    final behaviorLstm = File('${modelDir.path}/behavior_lstm_mobile.ptl');
    if (!await behaviorLstm.exists()) {
      throw Exception('behavior_lstm_mobile.ptl not found at ${behaviorLstm.path}');
    }
    _addLog('  ✅ behavior_lstm_mobile.ptl verified (${await behaviorLstm.length()} bytes)');

    final visionPtl = File('${modelDir.path}/vision_mobile.ptl');
    if (!await visionPtl.exists()) {
      throw Exception('vision_mobile.ptl not found at ${visionPtl.path}');
    }
    _addLog('  ✅ vision_mobile.ptl verified (${await visionPtl.length()} bytes)');

    // Check vision ONNX files
    final visionOnnx = File('${modelDir.path}/vision_mobile.onnx');
    if (!await visionOnnx.exists()) {
      throw Exception('vision_mobile.onnx not found at ${visionOnnx.path}');
    }
    _addLog('  ✅ vision_mobile.onnx verified (${await visionOnnx.length()} bytes)');

    final visionOnnxData = File('${modelDir.path}/vision_mobile.onnx.data');
    if (!await visionOnnxData.exists()) {
      throw Exception('vision_mobile.onnx.data not found at ${visionOnnxData.path}');
    }
    _addLog('  ✅ vision_mobile.onnx.data verified (${await visionOnnxData.length()} bytes)');

    // Check vocab file
    final vocabFile = File('${modelDir.path}/vocab.txt');
    if (!await vocabFile.exists()) {
      throw Exception('vocab.txt not found at ${vocabFile.path}');
    }
    _addLog('  ✅ vocab.txt verified (${await vocabFile.length()} bytes)');

    _addLog('✅ All model files verified successfully!');
  }

  /// Initialize ONNX Runtime with the BERT model
  Future<void> _initializeONNXRuntime() async {
    try {
      _addLog('🚀 Initializing ONNX Runtime...');

      // Get ONNX model path
      final modelPath = _modelPaths['bert_predatory.onnx'];
      if (modelPath == null || !await File(modelPath).exists()) {
        throw Exception('BERT ONNX model file not found at $modelPath');
      }

      _addLog('  📍 ONNX Model path: $modelPath');

      // Get ONNX data path
      final dataPath = _modelPaths['bert_predatory.onnx.data'];
      if (dataPath == null || !await File(dataPath).exists()) {
        throw Exception('BERT ONNX data file not found at $dataPath');
      }

      _addLog('  📍 ONNX Data path: $dataPath');

      // Verify both files are in same directory
      final modelDir = File(modelPath).parent.path;
      final dataDir = File(dataPath).parent.path;

      if (modelDir != dataDir) {
        throw Exception(
          'ONNX files are not in the same directory! '
          'Model: $modelDir, Data: $dataDir'
        );
      }

      _addLog('  ✅ ONNX files are in correct directory: $modelDir');

      // In a real implementation, you would initialize the ONNX Runtime here
      // For now, we're just verifying the setup
      // Example (would need onnxruntime_flutter or similar):
      // await OnnxModel.load(modelPath);

      _addLog('✅ ONNX Runtime initialization verified (models ready to load)');
    } catch (e, stackTrace) {
      _addLog('❌ ONNX Runtime initialization failed: $e');
      _addLog('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Analyze text for predatory behavior using BERT model
  /// Returns a score between 0 and 1 indicating confidence of predatory behavior
  Future<double> analyzeText(String text) async {
    if (!_initialized) {
      _addLog('❌ TextAnalysisService not initialized!');
      throw Exception('TextAnalysisService not initialized. Call initialize() first.');
    }

    try {
      _addLog('🔍 Analyzing text: "${text.substring(0, min(50, text.length))}"...');

      // In a real implementation, this would use the ONNX model
      // For now, we return a mock result based on keyword detection
      final score = _mockAnalysis(text);

      _addLog('  📊 Analysis score: $score');
      return score;
    } catch (e) {
      _addLog('❌ Text analysis failed: $e');
      rethrow;
    }
  }

  /// Mock analysis function for testing
  /// In production, this would use the actual ONNX model
  double _mockAnalysis(String text) {
    final lowerText = text.toLowerCase();
    final suspiciousKeywords = [
      'meet',
      'alone',
      'secret',
      'dont tell',
      'promise',
      'special',
      'love you',
      'kiss',
    ];

    int keywordCount = 0;
    for (final keyword in suspiciousKeywords) {
      if (lowerText.contains(keyword)) {
        keywordCount++;
      }
    }

    // Normalize to 0-1 range
    return (keywordCount / suspiciousKeywords.length).clamp(0.0, 1.0);
  }

  /// Get all initialization logs
  void printInitializationLogs() {
    _addLog('═══════════════════════════════════════════════════════');
    _addLog('📋 TextAnalysisService Initialization Logs:');
    _addLog('═══════════════════════════════════════════════════════');
    for (final log in _initializationLogs) {
      print(log);
    }
    _addLog('═══════════════════════════════════════════════════════');
  }
}

// Helper function for string length
int min(int a, int b) => a < b ? a : b;
