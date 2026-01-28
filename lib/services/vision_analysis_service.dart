import 'dart:io';
import 'package:pytorch_mobile/pytorch_mobile.dart';
import 'package:pytorch_mobile/model.dart';
import 'package:pytorch_mobile/enums/dtype.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Singleton service for analyzing images with vision model
class VisionAnalysisService {
  static final VisionAnalysisService _instance = VisionAnalysisService._internal();
  
  factory VisionAnalysisService() => _instance;
  
  VisionAnalysisService._internal();
  
  static VisionAnalysisService get instance => _instance;
  
  Model? _model;
  bool _isInitialized = false;
  
  // Cache for analyzed screenshots (hash -> scores)
  final Map<String, Map<String, double>> _analysisCache = {};
  static const int MAX_CACHE_SIZE = 50;
  
  bool get isInitialized => _isInitialized;
  
  /// Initialize the vision analysis service
  Future<bool> initialize() async {
    if (_isInitialized) {
      debugPrint('✅ VisionAnalysisService already initialized');
      return true;
    }
    
    try {
      debugPrint('🔄 Initializing VisionAnalysisService...');
      debugPrint('  Loading PyTorch vision model...');
      
      _model = await PyTorchMobile.loadModel('assets/models/vision_mobile.ptl');
      
      _isInitialized = true;
      debugPrint('✅ VisionAnalysisService initialized successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ VisionAnalysisService initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }
  
  /// Analyze a screenshot file
  Future<Map<String, double>> analyzeScreenshot(String imagePath) async {
    if (!_isInitialized) {
      throw Exception('VisionAnalysisService not initialized. Call initialize() first.');
    }
    
    try {
      // Load image from file
      final file = File(imagePath);
      if (!await file.exists()) {
        throw Exception('Screenshot file not found: $imagePath');
      }
      
      final bytes = await file.readAsBytes();
      
      // Check cache using file hash
      final hash = _calculateHash(bytes);
      if (_analysisCache.containsKey(hash)) {
        debugPrint('  📦 Using cached analysis result');
        return _analysisCache[hash]!;
      }
      
      // Decode image
      final image = img.decodeImage(bytes);
      if (image == null) {
        throw Exception('Failed to decode image: $imagePath');
      }
      
      // Analyze image
      final scores = await analyzeImage(image);
      
      // Cache result
      _cacheAnalysis(hash, scores);
      
      return scores;
    } catch (e) {
      debugPrint('❌ Error analyzing screenshot: $e');
      rethrow;
    }
  }
  
  /// Analyze an image with the vision model
  Future<Map<String, double>> analyzeImage(img.Image image) async {
    if (!_isInitialized || _model == null) {
      return {'safe': 1.0, 'explicit': 0.0, 'violence': 0.0, 'suggestive': 0.0};
    }
    
    try {
      // Resize image to model input size (224x224)
      final resized = img.copyResize(image, width: 224, height: 224);
      
      // Convert to normalized pixel values (0-1)
      final pixels = <double>[];
      for (int y = 0; y < 224; y++) {
        for (int x = 0; x < 224; x++) {
          final pixel = resized.getPixel(x, y);
          pixels.add(pixel.r / 255.0);
          pixels.add(pixel.g / 255.0);
          pixels.add(pixel.b / 255.0);
        }
      }
      
      // Run model inference
      final output = await _model!.getPrediction(
        pixels,
        [1, 3, 224, 224],
        DType.float32,
      );
      
      // Parse output
      List<double> logits;
      if (output is List) {
        // Assuming model outputs 4 classes: safe, explicit, violence, suggestive
        logits = (output as List)
            .map((e) => (e as num).toDouble())
            .toList()
            .sublist(0, math.min(4, (output as List).length));
        
        // Pad with zeros if less than 4 outputs
        while (logits.length < 4) {
          logits.add(0.0);
        }
      } else {
        debugPrint('⚠️  Unexpected model output format');
        return {'error': 1.0};
      }
      
      // Apply softmax to get probabilities
      final exp = logits.map((x) => math.exp(x)).toList();
      final sum = exp.reduce((a, b) => a + b);
      final probs = exp.map((x) => x / sum).toList();
      
      return {
        'safe': probs[0],
        'explicit': probs[1],
        'violence': probs[2],
        'suggestive': probs.length > 3 ? probs[3] : 0.0,
      };
    } catch (e) {
      debugPrint('❌ Error during image analysis: $e');
      return {'safe': 1.0, 'explicit': 0.0, 'violence': 0.0, 'suggestive': 0.0};
    }
  }
  
  /// Calculate hash of image bytes for caching
  String _calculateHash(List<int> bytes) {
    final digest = md5.convert(bytes);
    return digest.toString();
  }
  
  /// Cache analysis result
  void _cacheAnalysis(String hash, Map<String, double> scores) {
    // Remove oldest entry if cache is full
    if (_analysisCache.length >= MAX_CACHE_SIZE) {
      final firstKey = _analysisCache.keys.first;
      _analysisCache.remove(firstKey);
    }
    
    _analysisCache[hash] = scores;
  }
  
  /// Clear analysis cache
  void clearCache() {
    _analysisCache.clear();
    debugPrint('🗑️  Vision analysis cache cleared');
  }
  
  /// Get cache statistics
  Map<String, int> getCacheStats() {
    return {
      'size': _analysisCache.length,
      'maxSize': MAX_CACHE_SIZE,
    };
  }
}
