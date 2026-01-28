import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Service to extract text from images using Google ML Kit
class OCRService {
  static final OCRService _instance = OCRService._internal();
  
  factory OCRService() => _instance;
  
  OCRService._internal();
  
  static OCRService get instance => _instance;
  
  late TextRecognizer _textRecognizer;
  bool _isInitialized = false;

  void initialize() {
    if (_isInitialized) return;
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _isInitialized = true;
    debugPrint('✅ OCRService initialized');
  }

  /// Extract text from an image file at [imagePath]
  Future<String> extractText(String imagePath) async {
    if (!_isInitialized) initialize();
    
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        debugPrint('❌ OCRService: File does not exist $imagePath');
        return '';
      }

      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      
      final text = recognizedText.text;
      if (text.isNotEmpty) {
        debugPrint('📝 OCR Extracted ${text.length} chars from image');
      }
      
      return text;
    } catch (e) {
      debugPrint('❌ Error extracting text from image: $e');
      return '';
    }
  }

  void dispose() {
    if (_isInitialized) {
      _textRecognizer.close();
      _isInitialized = false;
    }
  }
}
