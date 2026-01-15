// lib/services/ai_model_service.dart
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

class AiModelService {
  // Singleton pattern
  static final AiModelService _instance = AiModelService._internal();
  factory AiModelService() => _instance;
  AiModelService._internal();

  Interpreter? _clipInterpreter;
  Interpreter? _lstmInterpreter;

  // Initialize interpreters (call once at app start)
  Future<void> init() async {
    _clipInterpreter = await _loadModel('assets/models/clip.tflite');
    _lstmInterpreter = await _loadModel('assets/models/lstm.tflite');
  }

  Future<Interpreter> _loadModel(String assetPath) async {
    final ByteData modelData = await rootBundle.load(assetPath);
    final Uint8List modelBytes = modelData.buffer.asUint8List();
    return Interpreter.fromBuffer(modelBytes);
  }

  // Example inference for CLIP model (placeholder implementation)
  List<double> runClipInference(List<double> input) {
    if (_clipInterpreter == null) {
      throw StateError('Clip interpreter not initialized. Call init() first.');
    }
    // Assuming input shape [1, 512] and output shape [1, 512]
    var inputTensor = input.reshape([1, input.length]);
    var output = List.filled(1 * input.length, 0.0).reshape([1, input.length]);
    _clipInterpreter!.run(inputTensor, output);
    return output[0];
  }

  // Example inference for LSTM model (placeholder implementation)
  List<double> runLstmInference(List<double> input) {
    if (_lstmInterpreter == null) {
      throw StateError('LSTM interpreter not initialized. Call init() first.');
    }
    var inputTensor = input.reshape([1, input.length]);
    var output = List.filled(1 * input.length, 0.0).reshape([1, input.length]);
    _lstmInterpreter!.run(inputTensor, output);
    return output[0];
  }
}

// Helper extension to reshape a flat list into a 2‑D list
extension ListReshape on List<double> {
  List<List<double>> reshape(List<int> dims) {
    if (dims.length != 2) {
      throw ArgumentError('Only 2‑D reshape is supported in this helper.');
    }
    int rows = dims[0];
    int cols = dims[1];
    if (rows * cols != length) {
      throw ArgumentError('Dimensions do not match list length.');
    }
    List<List<double>> result = [];
    for (int r = 0; r < rows; r++) {
      result.add(sublist(r * cols, (r + 1) * cols));
    }
    return result;
  }
}
