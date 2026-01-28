import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../model.dart';

class PyTorchMobile {
  static const MethodChannel _channel = MethodChannel('pytorch_mobile');

  /// Load a PyTorch model from the given asset path
  static Future<Model> loadModel(String assetPath) async {
    try {
      final String? modelPath = await _channel.invokeMethod<String>(
        'loadModel',
        {'assetPath': assetPath},
      );
      return Model(modelPath ?? assetPath);
    } catch (e) {
      // Return a model instance even on failure to allow graceful degradation
      return Model(assetPath);
    }
  }
}
