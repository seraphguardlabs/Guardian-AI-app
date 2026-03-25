import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../models/content_analysis_result.dart';
import '../utils/app_logger.dart';

class GemmaContentAnalyzer {
  final InferenceModel _model;

  InferenceChat? _chat;
  int _analysisCount = 0;
  static const int maxAnalysisPerSession = 10;

  GemmaContentAnalyzer(this._model);

  Future<ContentAnalysisResult> analyzeImage(
    Uint8List imageBytes, {
    String? appContext,
  }) async {
    int retryCount = 0;
    const maxRetries = 1;

    // Refine prompt based on context
    String contextInstruction = "";
    if (appContext != null) {
      final app = appContext.toLowerCase();
      if (app.contains('whatsapp') ||
          app.contains('messenger') ||
          app.contains('telegram') ||
          app.contains('snapchat')) {
        contextInstruction =
            " This is a Chat/Messaging app. Check for predatory grooming, severe bullying, or requests for private info/photos.";
      } else if (app.contains('chrome') || app.contains('browser')) {
        contextInstruction =
            " This is a Browser. Check for explicit, adult, or illegal content.";
      }
    }

    while (true) {
      final prompt = '''Safety classification from image.$contextInstruction
Output ONLY JSON (0.0 to 1.0, risk_score 0 to 100):
{"explicit":0.0, "violence":0.0, "predatory":0.0, "suggestive":0.0, "risk_score":0, "summary":"short reason"}''';

      try {
        // Reuse chat session to save battery and reduce lag
        if (_chat == null || _analysisCount >= maxAnalysisPerSession) {
          AppLogger.log('🔄 Creating new AI chat session (Count: $_analysisCount)');
          _chat = await _model.createChat(
            temperature: 0.1,
            topK: 40,
            supportImage: true,
          );
          _analysisCount = 0;
        }
        
        _analysisCount++;
        final message = Message.withImage(
          text: prompt,
          imageBytes: imageBytes,
          isUser: true,
        );
        await _chat!.addQuery(message);

        final responseBuffer = StringBuffer();
        await for (final modelResponse in _chat!.generateChatResponseAsync()) {
          if (modelResponse is TextResponse) {
            responseBuffer.write(modelResponse.token);
          }
        }

        final rawResponse = responseBuffer.toString();
        AppLogger.log(
          '🤖 AI Raw Response (${rawResponse.length} chars): $rawResponse',
        );

        try {
          final result = _parseAnalysisResponse(rawResponse);
          AppLogger.log(
            '✅ AI Parsed: Score=${result.riskScore}, Summary="${result.summary}"',
          );
          return result;
        } catch (e) {
          AppLogger.log('⚠️ AI Parse Failed: $e');
          return ContentAnalysisResult.safe();
        }
      } catch (e, st) {
        AppLogger.logError('❌ AI Generation Error', e, st);
        final errStr = e.toString().toLowerCase();
        if ((errStr.contains('range') ||
                errStr.contains('token') ||
                errStr.contains('limit')) &&
            retryCount < maxRetries) {
          retryCount++;
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        return ContentAnalysisResult.safe();
      }
    }
  }

  ContentAnalysisResult _parseAnalysisResponse(String response) {
    try {
      final parsed = _parseJsonResponse(response);

      return ContentAnalysisResult(
        riskScore: ((parsed['risk_score'] as num?)?.toInt() ?? 0).clamp(0, 100),
        categories: {
          'explicit': ((parsed['explicit'] as num?)?.toDouble() ?? 0.0).clamp(
            0.0,
            1.0,
          ),
          'violence': ((parsed['violence'] as num?)?.toDouble() ?? 0.0).clamp(
            0.0,
            1.0,
          ),
          'predatory': ((parsed['predatory'] as num?)?.toDouble() ?? 0.0).clamp(
            0.0,
            1.0,
          ),
          'suggestive': ((parsed['suggestive'] as num?)?.toDouble() ?? 0.0)
              .clamp(0.0, 1.0),
        },
        summary: parsed['summary'] as String? ?? 'Analysis completed.',
      );
    } catch (e) {
      debugPrint('⚠️ JSON parse failed, trying regex fallback');
      return _parseWithRegexFallback(response);
    }
  }

  Map<String, dynamic> _parseJsonResponse(String response) {
    try {
      return jsonDecode(response) as Map<String, dynamic>;
    } catch (_) {}

    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      try {
        return jsonDecode(response.substring(start, end + 1))
            as Map<String, dynamic>;
      } catch (_) {}
    }
    throw const FormatException('No valid JSON found');
  }

  ContentAnalysisResult _parseWithRegexFallback(String response) {
    final result = <String, dynamic>{};
    final lower = response.toLowerCase();

    for (final field in ['explicit', 'violence', 'predatory', 'suggestive']) {
      final pattern = RegExp('\$field"?\\s*:\\s*([0-9.]+)');
      final match = pattern.firstMatch(lower);
      if (match != null) {
        result[field] = double.tryParse(match.group(1)!) ?? 0.0;
      }
    }

    final riskPattern = RegExp(r'risk_score"?\s*:\s*(\d+)');
    final riskMatch = riskPattern.firstMatch(lower);
    if (riskMatch != null) {
      result['risk_score'] = int.tryParse(riskMatch.group(1)!) ?? 0;
    }

    final summaryPattern = RegExp(r'summary"?\s*:\s*"([^"]+)"');
    final summaryMatch = summaryPattern.firstMatch(response);
    if (summaryMatch != null) {
      result['summary'] = summaryMatch.group(1);
    }

    if (result.isEmpty) return ContentAnalysisResult.safe();

    return ContentAnalysisResult(
      riskScore: ((result['risk_score'] as int?) ?? 0).clamp(0, 100),
      categories: {
        'explicit': ((result['explicit'] as double?) ?? 0.0).clamp(0.0, 1.0),
        'violence': ((result['violence'] as double?) ?? 0.0).clamp(0.0, 1.0),
        'predatory': ((result['predatory'] as double?) ?? 0.0).clamp(0.0, 1.0),
        'suggestive': ((result['suggestive'] as double?) ?? 0.0).clamp(
          0.0,
          1.0,
        ),
      },
      summary:
          (result['summary'] as String?) ??
          'Analysis completed (regex fallback).',
    );
  }
}
