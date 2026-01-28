import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'enums/dtype.dart';

class Model {
  final String modelPath;
  static const MethodChannel _channel = MethodChannel('pytorch_mobile');

  Model(this.modelPath);

  /// Run inference on the model with the given input data
  /// Returns prediction result from the model
  Future<List<double>?> getPrediction(
    List<double> input,
    List<int> shape,
    DType dtype,
  ) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'predict',
        {
          'modelPath': modelPath,
          'input': Float64List.fromList(input),
          'shape': shape,
          'dtype': dtype.index,
        },
      );
      return result?.cast<double>();
    } catch (e) {
      // Return null on failure for graceful degradation
      return null;
    }
  }

  /// Run inference with int input (for NLP models with token IDs)
  Future<List<double>?> getPredictionInt(
    List<int> input,
    List<int> shape,
    DType dtype,
  ) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'predictInt',
        {
          'modelPath': modelPath,
          'input': Int64List.fromList(input),
          'shape': shape,
          'dtype': dtype.index,
        },
      );
      return result?.cast<double>();
    } catch (e) {
      return null;
    }
  }

  /// Get image prediction from raw bytes
  Future<List<double>?> getImagePrediction(
    Uint8List imageData,
    int width,
    int height,
    String? mean,
    String? std,
  ) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'predictImage',
        {
          'modelPath': modelPath,
          'imageData': imageData,
          'width': width,
          'height': height,
          'mean': mean,
          'std': std,
        },
      );
      return result?.cast<double>();
    } catch (e) {
      return null;
    }
  }
}
