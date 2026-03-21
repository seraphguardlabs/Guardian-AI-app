import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../models/content_analysis_result.dart';
import '../utils/app_logger.dart';

class GemmaContentAnalyzer {
  final InferenceModel _model;
  final Map<String, ContentAnalysisResult> _textCache = {};

  GemmaContentAnalyzer(this._model);

  /// Describe the screenshot in natural language first (gemma3n flow).
  Future<String> describeImageWithChat(
    InferenceChat chat,
    Uint8List imageBytes,
  ) async {
    const describePrompt =
        'In exactly 2 short sentences, describe what is on this screen: who is visible, what actions are happening, and whether there is any dangerous, violent, or suggestive content. Then on a new line write "risk:" followed by a number 0-100.';

    try {
      final message = Message.withImage(
        text: describePrompt,
        imageBytes: imageBytes,
        isUser: true,
      );
      await chat.addQuery(message);

      final buffer = StringBuffer();
      await for (final modelResponse in chat.generateChatResponseAsync()) {
        if (modelResponse is TextResponse) {
          buffer.write(modelResponse.token);
        }
      }

      final description = buffer.toString().trim();
      await chat.clearHistory();

      AppLogger.log(
        '[GemmaAnalyzer] Description generated (${description.length} chars)',
      );
      return description;
    } catch (e, st) {
      AppLogger.logError('[GemmaAnalyzer] describeImageWithChat failed', e, st);
      return '';
    }
  }

  /// Analyze textual screen description for safety categories (gemma3n flow).
  Future<ContentAnalysisResult> analyzeText(
    String text, {
    String? foregroundApp,
    bool useCache = true,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return ContentAnalysisResult.safe();
    }

    if (useCache && _textCache.containsKey(normalized)) {
      return _textCache[normalized]!;
    }

    try {
      final session = await _model.createChat(
        temperature: 0.2,
        topK: 20,
        supportImage: false,
      );

      final prompt = '''You are a child-safety content classifier. Given the following screen description, rate it on these categories from 0.0 to 1.0:
- explicit: sexual or adult content
- violence: violent or gore content
- predatory: grooming or predatory behaviour
- suggestive: mildly inappropriate content

Also provide an overall risk score from 0 to 100 and a one-line summary.

Respond ONLY in this exact format (no extra text):
explicit:0.0
violence:0.0
predatory:0.0
suggestive:0.0
risk:0
summary:One line summary here

Screen description: $normalized
${foregroundApp != null ? 'Foreground app: $foregroundApp' : ''}''';

      await session.addQuery(Message(text: prompt, isUser: true));

      final responseBuffer = StringBuffer();
      await for (final modelResponse in session.generateChatResponseAsync()) {
        if (modelResponse is TextResponse) {
          responseBuffer.write(modelResponse.token);
        }
      }

      await session.clearHistory();

      final result = _parseTextClassifierResponse(responseBuffer.toString());
      if (useCache) {
        _textCache[normalized] = result;
      }
      return result;
    } catch (e, st) {
      AppLogger.logError('[GemmaAnalyzer] analyzeText failed', e, st);
      return ContentAnalysisResult.safe();
    }
  }

  /// Analyzes an image using a persistsent chat context.
  /// This is much faster than creating a new chat every time.
  Future<ContentAnalysisResult> analyzeWithChat(InferenceChat chat, Uint8List imageBytes) async {
    final prompt = '''Safety classification from image.
Output ONLY JSON (0.0 to 1.0, risk_score 0 to 100):
{"explicit":0.0, "violence":0.0, "predatory":0.0, "suggestive":0.0, "risk_score":0, "summary":"short reason"}''';

    try {
      final message = Message.withImage(
        text: prompt,
        imageBytes: imageBytes,
        isUser: true,
      );
      await chat.addQuery(message);

      final responseBuffer = StringBuffer();
      await for (final modelResponse in chat.generateChatResponseAsync()) {
        if (modelResponse is TextResponse) {
          responseBuffer.write(modelResponse.token);
        }
      }

      final rawResponse = responseBuffer.toString();
      debugPrint('🔍 Raw Gemma Image response: ${rawResponse.substring(0, rawResponse.length.clamp(0, 500))}');
      
      return _parseAnalysisResponse(rawResponse);
    } catch (e) {
      debugPrint('❌ GemmaContentAnalyzer withChat error: $e');
      return ContentAnalysisResult.safe();
    }
  }

  Future<ContentAnalysisResult> analyzeImage(Uint8List imageBytes) async {
    int retryCount = 0;
    const maxRetries = 1;

    while (true) {
      final prompt = '''Safety classification from image.
Output ONLY JSON (0.0 to 1.0, risk_score 0 to 100):
{"explicit":0.0, "violence":0.0, "predatory":0.0, "suggestive":0.0, "risk_score":0, "summary":"short reason"}''';

      InferenceChat? chat;
      try {
        chat = await _model.createChat(
          temperature: 0.1,
          topK: 40,
          supportImage: true,
        );
        final message = Message.withImage(
          text: prompt,
          imageBytes: imageBytes,
          isUser: true,
        );
        await chat.addQuery(message);

        final responseBuffer = StringBuffer();
        await for (final modelResponse in chat.generateChatResponseAsync()) {
          if (modelResponse is TextResponse) {
            responseBuffer.write(modelResponse.token);
          }
        }

        final rawResponse = responseBuffer.toString();
        debugPrint('🔍 Raw Gemma Image response: ${rawResponse.substring(0, rawResponse.length.clamp(0, 500))}');
        
        return _parseAnalysisResponse(rawResponse);
      } catch (e) {
        debugPrint('❌ GemmaContentAnalyzer Image error: $e');
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
          'explicit': ((parsed['explicit'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
          'violence': ((parsed['violence'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
          'predatory': ((parsed['predatory'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
          'suggestive': ((parsed['suggestive'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
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
        'suggestive': ((result['suggestive'] as double?) ?? 0.0).clamp(0.0, 1.0),
      },
      summary: (result['summary'] as String?) ?? 'Analysis completed (regex fallback).',
    );
  }

  ContentAnalysisResult _parseTextClassifierResponse(String response) {
    final categories = <String, double>{
      'explicit': 0.0,
      'violence': 0.0,
      'predatory': 0.0,
      'suggestive': 0.0,
    };
    int riskScore = 0;
    String summary = 'No summary available';

    for (final line in response.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final colonIndex = trimmed.indexOf(':');
      if (colonIndex == -1) continue;

      final key = trimmed.substring(0, colonIndex).trim().toLowerCase();
      final value = trimmed.substring(colonIndex + 1).trim();

      switch (key) {
        case 'explicit':
        case 'violence':
        case 'predatory':
        case 'suggestive':
          categories[key] = (double.tryParse(value) ?? 0.0).clamp(0.0, 1.0);
          break;
        case 'risk':
          riskScore = (int.tryParse(value) ?? 0).clamp(0, 100);
          break;
        case 'summary':
          summary = value;
          break;
      }
    }

    return ContentAnalysisResult(
      riskScore: riskScore,
      categories: categories,
      summary: summary,
    );
  }
}
