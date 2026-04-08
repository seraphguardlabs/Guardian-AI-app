import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'models/risk_result.dart';
import 'services/app_config_repository.dart';
import 'services/guardian_platform.dart';
import 'services/model_repository.dart';

const String _gemmaModelName = String.fromEnvironment(
  'GEMMA4_MODEL_NAME',
  defaultValue: 'Gemma-4-E2B-it',
);
const String _gemmaModelId = String.fromEnvironment(
  'GEMMA4_MODEL_ID',
  defaultValue: 'litert-community/gemma-4-E2B-it-litert-lm',
);
const String _gemmaModelUrl = String.fromEnvironment(
  'GEMMA4_MODEL_URL',
  defaultValue: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true',
);
const String _gemmaModelFileName = String.fromEnvironment(
  'GEMMA4_MODEL_FILE',
  defaultValue: 'gemma-4-E2B-it.litertlm',
);
const String _gemmaHfToken = String.fromEnvironment(
  'GEMMA4_HF_TOKEN',
  defaultValue: '',
);

void main() {
  runApp(const GuardianApp());
}

class GuardianApp extends StatelessWidget {
  const GuardianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guardian AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF245E4F)),
      ),
      home: const GuardianHomePage(),
    );
  }
}

class GuardianHomePage extends StatefulWidget {
  const GuardianHomePage({super.key});

  @override
  State<GuardianHomePage> createState() => _GuardianHomePageState();
}

class _GuardianHomePageState extends State<GuardianHomePage> {
  final GuardianPlatform _platform = GuardianPlatform();
  final AppConfigRepository _configRepository = const AppConfigRepository(
    defaultModelName: _gemmaModelName,
    defaultModelId: _gemmaModelId,
    defaultModelUrl: _gemmaModelUrl,
    defaultModelFileName: _gemmaModelFileName,
    defaultHfToken: _gemmaHfToken,
  );

  final TextEditingController _modelUrlController = TextEditingController();
  final TextEditingController _modelFileController = TextEditingController();
  final TextEditingController _hfTokenController = TextEditingController();

  Timer? _pollingTimer;
  AppConfig? _config;
  String? _modelPath;
  String _status = 'Idle';
  bool _isBusy = false;
  bool _autoBootInProgress = false;
  bool _waitingForPermission = false;
  bool _monitoringEnabled = false;
  bool _accessibilityEnabled = false;
  double _downloadProgress = 0;
  bool _autoStart = true;
  int _intervalSeconds = 5;
  RiskResult? _latest;
  List<RiskResult> _history = <RiskResult>[];

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) async {
        await _refreshState();
        if (_waitingForPermission && _accessibilityEnabled && !_monitoringEnabled && !_isBusy) {
          await _continueAfterPermissionGranted();
        }
      },
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _modelUrlController.dispose();
    _modelFileController.dispose();
    _hfTokenController.dispose();
    super.dispose();
  }

  ModelRepository _repositoryFromConfig(AppConfig config) {
    return ModelRepository(
      modelId: config.modelId,
      modelUrl: config.modelUrl,
      modelFileName: config.modelFileName,
      hfToken: config.hfToken,
    );
  }

  Future<void> _bootstrap() async {
    final config = await _configRepository.load();
    _modelUrlController.text = config.modelUrl;
    _modelFileController.text = config.modelFileName;
    _hfTokenController.text = config.hfToken;

    if (!mounted) {
      return;
    }

    setState(() {
      _config = config;
      _autoStart = config.autoStart;
      _status = config.isReadyForDownload
          ? 'Ready to initialize ${config.modelName}.'
          : 'Add model URL, then Save and Start.';
    });

    await _refreshState();
    if (_autoStart) {
      await _runSetupAndStart(openSettingsIfNeeded: true);
    }
  }

  Future<void> _saveConfig() async {
    final current = _config;
    if (current == null) {
      return;
    }

    final updated = current.copyWith(
      modelUrl: _modelUrlController.text.trim(),
      modelFileName: _modelFileController.text.trim(),
      hfToken: _hfTokenController.text.trim(),
      autoStart: _autoStart,
    );

    await _configRepository.save(updated);
    if (!mounted) {
      return;
    }

    setState(() {
      _config = updated;
      _status = 'Configuration saved.';
    });
  }

  Future<void> _refreshState() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      final enabled = await _platform.isAccessibilityServiceEnabled();
      final latest = await _platform.getLatestRiskResult();
      final recent = await _platform.getRecentRiskResults(limit: 25);

      if (!mounted) {
        return;
      }

      setState(() {
        _accessibilityEnabled = enabled;
        _latest = latest;
        _history = recent;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Native bridge not ready yet.';
      });
    }
  }

  Future<void> _reloadAccessibilityStatus() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _status = 'Refreshing accessibility permission status...';
    });

    await _refreshState();
    if (!mounted) {
      return;
    }

    setState(() {
      _status = _accessibilityEnabled
          ? 'Accessibility permission detected as enabled.'
          : 'Accessibility permission is still disabled.';
    });

    if (_accessibilityEnabled && _waitingForPermission && !_isBusy && !_monitoringEnabled) {
      await _continueAfterPermissionGranted();
    }
  }

  Future<void> _downloadAndInstallModel(AppConfig config) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _downloadProgress = 0;
      _status = 'Step 1/4: Downloading ${config.modelName}... 0%';
    });

    final path = await _repositoryFromConfig(config).ensureModelAvailable(
      onProgress: (value) {
        if (!mounted) {
          return;
        }
        final clamped = value.clamp(0.0, 1.0);
        setState(() {
          _downloadProgress = clamped;
          _status = 'Step 1/4: Downloading ${config.modelName}... '
              '${(clamped * 100).toStringAsFixed(0)}%';
        });
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _status = 'Step 2/4: Installing ${config.modelName} on device...';
    });

    await _platform.initializeModel(
      modelPath: path,
      modelId: config.modelId,
      hfToken: config.hfToken,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _modelPath = path;
      _downloadProgress = 1;
      _status = 'Step 2/4: Model installed locally.';
    });
  }

  Future<void> _startMonitoringOnly(AppConfig config) async {
    if (!_accessibilityEnabled) {
      throw Exception('Accessibility permission not enabled.');
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _status = 'Step 4/4: Starting monitoring...';
    });

    await _platform.setMonitoringEnabled(
      enabled: true,
      intervalSeconds: _intervalSeconds,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _monitoringEnabled = true;
      _waitingForPermission = false;
      _status = 'Setup complete. Monitoring active.';
    });
  }

  Future<void> _runSetupAndStart({bool openSettingsIfNeeded = true}) async {
    final config = _config;
    if (config == null) {
      return;
    }

    if (!config.isReadyForDownload) {
      setState(() {
        _status = 'Set a valid model URL before starting setup.';
      });
      return;
    }

    if (_autoBootInProgress) {
      return;
    }

    _autoBootInProgress = true;

    try {
      if (mounted) {
        setState(() {
          _isBusy = true;
          _waitingForPermission = false;
        });
      }

      await _downloadAndInstallModel(config);
      await _refreshState();

      if (!_accessibilityEnabled) {
        if (!mounted) {
          return;
        }

        setState(() {
          _waitingForPermission = true;
          _isBusy = false;
          _status =
              'Step 3/4: Enable accessibility permission. Monitoring will auto-start once enabled.';
        });

        if (openSettingsIfNeeded) {
          await _openAccessibilitySettings(
            statusOverride:
                'Step 3/4: Enable accessibility permission. Monitoring will auto-start once enabled.',
          );
        }
        return;
      }

      await _startMonitoringOnly(config);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'Setup failed: $e';
      });
    } finally {
      _autoBootInProgress = false;
      if (mounted) {
        setState(() {
          if (!_waitingForPermission) {
            _isBusy = false;
          }
        });
      }
    }
  }

  Future<void> _continueAfterPermissionGranted() async {
    if (!_waitingForPermission || _isBusy || _monitoringEnabled) {
      return;
    }

    final config = _config;
    if (config == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isBusy = true;
      _waitingForPermission = false;
      _status = 'Step 3/4: Permission granted. Continuing setup...';
    });

    try {
      await _startMonitoringOnly(config);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'Unable to start monitoring after permission: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _stopMonitoring() async {
    setState(() {
      _isBusy = true;
      _status = 'Stopping monitoring...';
    });

    try {
      await _platform.setMonitoringEnabled(
        enabled: false,
        intervalSeconds: _intervalSeconds,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _monitoringEnabled = false;
        _status = 'Monitoring stopped.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'Unable to stop monitoring: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _openAccessibilitySettings({String? statusOverride}) async {
    try {
      await _platform.openAccessibilitySettings();
      if (!mounted) {
        return;
      }
      setState(() {
        _status =
            statusOverride ?? 'Enable Guardian accessibility service and return.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Failed to open accessibility settings: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return Scaffold(
        appBar: AppBar(title: const Text('Guardian AI')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'This prototype currently supports Android only for background screenshots.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Guardian AI - ${_config?.modelName ?? _gemmaModelName}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('First-run setup (saved on device)'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _modelUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Model URL',
                      hintText: 'https://huggingface.co/.../resolve/main/model-file',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _modelFileController,
                    decoration: const InputDecoration(
                      labelText: 'Model file name',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _hfTokenController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'HF token (for gated models)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto start after app opens'),
                    value: _autoStart,
                    onChanged: (value) {
                      setState(() {
                        _autoStart = value;
                      });
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _isBusy
                            ? null
                            : () async {
                                await _saveConfig();
                                await _runSetupAndStart(openSettingsIfNeeded: true);
                              },
                        child: const Text('Save and Start'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status: $_status'),
                  const SizedBox(height: 8),
                  Text(
                    'Selected model: ${_config?.modelName ?? _gemmaModelName} '
                    '(${_config?.modelId ?? _gemmaModelId})',
                  ),
                  const SizedBox(height: 8),
                  Text('Accessibility service enabled: $_accessibilityEnabled'),
                  const SizedBox(height: 8),
                  Text('Waiting for permission: $_waitingForPermission'),
                  const SizedBox(height: 8),
                  Text('Monitoring active: $_monitoringEnabled'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _isBusy ? null : _reloadAccessibilityStatus,
                        child: const Text('Reload accessibility status'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Model path: ${_modelPath ?? 'Not prepared yet'}'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _downloadProgress > 0 ? _downloadProgress : null,
                    minHeight: 8,
                  ),
                  const SizedBox(height: 8),
                  Text('Download progress: ${(_downloadProgress * 100).toStringAsFixed(0)}%'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Screenshot interval (seconds)'),
                  Slider(
                    min: 2,
                    max: 15,
                    divisions: 13,
                    value: _intervalSeconds.toDouble(),
                    label: '$_intervalSeconds',
                    onChanged: _isBusy
                        ? null
                        : (value) {
                            setState(() {
                              _intervalSeconds = value.round();
                            });
                          },
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _isBusy
                            ? null
                            : () async {
                                await _saveConfig();
                                await _runSetupAndStart(openSettingsIfNeeded: true);
                              },
                        child: const Text('Run Setup and Start'),
                      ),
                      if (_waitingForPermission)
                        OutlinedButton(
                          onPressed: _isBusy
                              ? null
                              : () => _openAccessibilitySettings(
                                    statusOverride:
                                        'Step 3/4: Enable accessibility permission. Monitoring will auto-start once enabled.',
                                  ),
                          child: const Text('Open accessibility settings'),
                        ),
                      OutlinedButton(
                        onPressed: _isBusy || !_monitoringEnabled ? null : _stopMonitoring,
                        child: const Text('Stop monitoring'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Latest risk snapshot'),
                  const SizedBox(height: 8),
                  if (_latest == null)
                    const Text('No screenshot scored yet.')
                  else
                    Text(
                      'Overall: ${_latest!.overall.toStringAsFixed(2)}\n'
                      'Sexual: ${_latest!.sexual.toStringAsFixed(2)}\n'
                      'Violence: ${_latest!.violence.toStringAsFixed(2)}\n'
                      'Predatory text: ${_latest!.predatoryText.toStringAsFixed(2)}\n'
                      'At: ${_latest!.timestamp}',
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Recent history'),
                  const SizedBox(height: 8),
                  for (final result in _history.take(10))
                    Text(
                      '${result.timestamp.toLocal()}  |  total ${result.overall.toStringAsFixed(2)} '
                      '(S:${result.sexual.toStringAsFixed(2)} V:${result.violence.toStringAsFixed(2)} '
                      'P:${result.predatoryText.toStringAsFixed(2)})',
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
