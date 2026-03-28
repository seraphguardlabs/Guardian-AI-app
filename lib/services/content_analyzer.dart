import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../models/content_analysis_result.dart';
import '../utils/app_logger.dart';

/// Describes what the analyzer produces for each frame.
class AnalysisEvent {
  final String description;
  final ContentAnalysisResult result;
  final DateTime timestamp;

  const AnalysisEvent({
    required this.description,
    required this.result,
    required this.timestamp,
  });
}

/// Consumes raw JPEG frames and produces safety [AnalysisEvent]s.
///
/// Mirrors gemma3n's two-step pipeline verbatim:
///   Step 1 — vision chat: describe what is on screen in natural language.
///   Step 2 — text chat:   classify the description into safety categories.
///
/// Frame-drop policy: if [isBusy], the incoming frame is silently discarded.
/// This prevents memory pressure from a building backlog.
class ContentAnalyzer {
  final InferenceModel _model;

  ContentAnalyzer(this._model);

  // ── Public state ──────────────────────────────────────────────────────────
  bool _busy = false;
  bool get isBusy => _busy;

  int _framesAnalyzed = 0;
  int get framesAnalyzed => _framesAnalyzed;

  final _streamController = StreamController<AnalysisEvent>.broadcast();
  Stream<AnalysisEvent> get analysisStream => _streamController.stream;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Process one JPEG frame. Drop silently if already busy.
  Future<void> processFrame(Uint8List imageBytes) async {
    if (_busy) {
      AppLogger.log('[ContentAnalyzer] ⚠️ Busy — frame dropped');
      return;
    }
    _busy = true;
    final sw = Stopwatch()..start();
    try {
      _framesAnalyzed++;
      AppLogger.log('[ContentAnalyzer] 🧠 Analyzing frame #$_framesAnalyzed (${imageBytes.length} bytes)…');

      // ── Step 1: Vision — describe the screen ─────────────────────────────
      final visionSession = await _model.createChat(
        temperature: 0.4,
        topK: 40,
        supportImage: true,
      );

      const describePrompt =
          'In exactly 2 short sentences, describe what is on this screen: '
          'who is visible, what actions are happening, and whether there is any '
          'dangerous, violent, or suggestive content. '
          'Then on a new line write "risk:" followed by a number 0-100.';

      final descMsg = Message.withImage(
        text: describePrompt,
        imageBytes: imageBytes,
        isUser: true,
      );
      await visionSession.addQuery(descMsg);

      final descBuffer = StringBuffer();
      await for (final r in visionSession.generateChatResponseAsync()) {
        if (r is TextResponse) descBuffer.write(r.token);
      }
      final description = descBuffer.toString().trim();
      await visionSession.clearHistory();

      AppLogger.log('[ContentAnalyzer] 📝 Description: '
          '${description.substring(0, description.length.clamp(0, 120))}…');

      if (description.isEmpty) {
        AppLogger.log('[ContentAnalyzer] Empty description — skipping safety step');
        return;
      }

      // ── Step 2: Safety classification ────────────────────────────────────
      final safetyResult = await _classifyText(description);

      sw.stop();
      AppLogger.log(
        '[ContentAnalyzer] ✅ Done in ${sw.elapsedMilliseconds}ms — '
        'risk=${safetyResult.riskScore}/100 | ${safetyResult.summary}',
      );

      if (!_streamController.isClosed) {
        _streamController.add(AnalysisEvent(
          description: description,
          result: safetyResult,
          timestamp: DateTime.now(),
        ));
      }
    } catch (e, st) {
      sw.stop();
      AppLogger.logError(
        '[ContentAnalyzer] Frame analysis failed (${sw.elapsedMilliseconds}ms)',
        e,
        st,
      );
    } finally {
      _busy = false;
    }
  }

  // ── Internal: text classification (Step 2) ────────────────────────────────
  Future<ContentAnalysisResult> _classifyText(String description) async {
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

Screen description: $description''';

      await session.addQuery(Message(text: prompt, isUser: true));

      final buf = StringBuffer();
      await for (final r in session.generateChatResponseAsync()) {
        if (r is TextResponse) buf.write(r.token);
      }
      await session.clearHistory();

      return _parseClassifierResponse(buf.toString());
    } catch (e, st) {
      AppLogger.logError('[ContentAnalyzer] _classifyText failed', e, st);
      return ContentAnalysisResult.safe();
    }
  }

  // ── Parser (identical to gemma3n) ─────────────────────────────────────────
  ContentAnalysisResult _parseClassifierResponse(String response) {
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
      final idx = trimmed.indexOf(':');
      if (idx == -1) continue;
      final key = trimmed.substring(0, idx).trim().toLowerCase();
      final val = trimmed.substring(idx + 1).trim();

      switch (key) {
        case 'explicit':
        case 'violence':
        case 'predatory':
        case 'suggestive':
          categories[key] = (double.tryParse(val) ?? 0.0).clamp(0.0, 1.0);
          break;
        case 'risk':
          riskScore = (int.tryParse(val) ?? 0).clamp(0, 100);
          break;
        case 'summary':
          summary = val;
          break;
      }
    }

    return ContentAnalysisResult(
      riskScore: riskScore,
      categories: categories,
      summary: summary,
    );
  }

  void dispose() {
    _streamController.close();
  }
}
