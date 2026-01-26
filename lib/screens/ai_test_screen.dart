import 'package:flutter/material.dart';
import '../services/text_analysis_service.dart';

class AITestScreen extends StatefulWidget {
  const AITestScreen({super.key});

  @override
  State<AITestScreen> createState() => _AITestScreenState();
}

class _AITestScreenState extends State<AITestScreen> {
  late TextAnalysisService _textAnalysisService;
  bool _isInitialized = false;
  bool _isInitializing = false;
  List<String> _logs = [];
  String _testText = 'Let\'s meet alone';
  double? _analysisScore;
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _textAnalysisService = TextAnalysisService.instance;
    _addLog('🚀 AI Test Screen initialized');
  }

  void _addLog(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toIso8601String()}] $message');
    });
  }

  Future<void> _initializeModels() async {
    if (_isInitialized || _isInitializing) {
      _addLog('⚠️  Already initializing or initialized');
      return;
    }

    setState(() => _isInitializing = true);

    try {
      _addLog('🔄 Starting model initialization...');
      final success = await _textAnalysisService.initialize();

      if (success) {
        _addLog('✅ Model initialization SUCCESSFUL!');
        setState(() {
          _isInitialized = true;
          _logs.addAll(_textAnalysisService.initializationLogs);
        });
      } else {
        _addLog('❌ Model initialization FAILED!');
        setState(() {
          _logs.addAll(_textAnalysisService.initializationLogs);
        });
      }
    } catch (e, stackTrace) {
      _addLog('❌ Error during initialization: $e');
      _addLog('Stack trace: $stackTrace');
    } finally {
      setState(() => _isInitializing = false);
    }
  }

  Future<void> _analyzeText() async {
    if (!_isInitialized) {
      _addLog('❌ Models not initialized! Please initialize first.');
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      _addLog('🔍 Analyzing text: "$_testText"...');
      final score = await _textAnalysisService.analyzeText(_testText);

      setState(() {
        _analysisScore = score;
        _addLog(
          '✅ Analysis complete! '
          'Score: ${(score * 100).toStringAsFixed(2)}% '
          'Risk: ${_getRiskLevel(score)}'
        );
      });
    } catch (e) {
      _addLog('❌ Analysis error: $e');
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  String _getRiskLevel(double score) {
    if (score < 0.3) return '🟢 Low';
    if (score < 0.6) return '🟡 Medium';
    return '🔴 High';
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
      _addLog('📋 Logs cleared');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🤖 AI Model Test'),
        centerTitle: true,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status section
              _buildStatusCard(),
              const SizedBox(height: 16),

              // Initialize button
              _buildInitializeSection(),
              const SizedBox(height: 16),

              // Test analysis section
              if (_isInitialized) ...[
                _buildTestAnalysisSection(),
                const SizedBox(height: 16),
              ],

              // Logs section
              _buildLogsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Service Initialized: '),
                Text(
                  _isInitialized ? '✅ Yes' : '❌ No',
                  style: TextStyle(
                    color: _isInitialized ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_isInitialized && _textAnalysisService.modelBasePath != null)
              Text(
                'Models Path: ${_textAnalysisService.modelBasePath}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            const SizedBox(height: 8),
            if (_analysisScore != null)
              Row(
                children: [
                  const Text('Last Analysis Score: '),
                  Text(
                    '${(_analysisScore! * 100).toStringAsFixed(2)}% '
                    '${_getRiskLevel(_analysisScore!)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitializeSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚙️ Initialization',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isInitializing || _isInitialized
                    ? null
                    : _initializeModels,
                icon: _isInitializing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.cloud_download),
                label: Text(
                  _isInitializing
                      ? 'Initializing...'
                      : _isInitialized
                          ? 'Models Initialized'
                          : 'Initialize Models',
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Click to load AI models from device storage',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestAnalysisSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🔍 Test Text Analysis',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              maxLines: 3,
              onChanged: (value) => setState(() => _testText = value),
              decoration: InputDecoration(
                hintText: 'Enter text to analyze...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                labelText: 'Text Input',
              ),
              controller: TextEditingController(text: _testText),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isAnalyzing ? null : _analyzeText,
                icon: _isAnalyzing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.search_rounded),
                label: Text(_isAnalyzing ? 'Analyzing...' : 'Analyze Text'),
              ),
            ),
            if (_analysisScore != null) ...[
              const SizedBox(height: 16),
              _buildScoreDisplay(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScoreDisplay() {
    final score = _analysisScore!;
    final percentage = (score * 100).toStringAsFixed(2);
    final riskLevel = _getRiskLevel(score);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Analysis Result:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: score,
            minHeight: 30,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              score < 0.3 ? Colors.green : score < 0.6 ? Colors.orange : Colors.red,
            ),
            semanticsLabel: 'Risk level',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Score: $percentage%',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              riskLevel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLogsSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📋 Debug Logs',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_logs.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clearLogs,
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(minHeight: 200),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SelectableText(
                    _logs.isEmpty
                        ? '📝 Logs will appear here...\n\nClick "Initialize Models" to start.'
                        : _logs.join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
