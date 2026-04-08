import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  const AppConfig({
    required this.modelName,
    required this.modelId,
    required this.modelUrl,
    required this.modelFileName,
    required this.hfToken,
    required this.autoStart,
  });

  final String modelName;
  final String modelId;
  final String modelUrl;
  final String modelFileName;
  final String hfToken;
  final bool autoStart;

  AppConfig copyWith({
    String? modelName,
    String? modelId,
    String? modelUrl,
    String? modelFileName,
    String? hfToken,
    bool? autoStart,
  }) {
    return AppConfig(
      modelName: modelName ?? this.modelName,
      modelId: modelId ?? this.modelId,
      modelUrl: modelUrl ?? this.modelUrl,
      modelFileName: modelFileName ?? this.modelFileName,
      hfToken: hfToken ?? this.hfToken,
      autoStart: autoStart ?? this.autoStart,
    );
  }

  bool get isReadyForDownload => modelUrl.trim().isNotEmpty && !modelUrl.contains('example.com');
}

class AppConfigRepository {
  static const String _keyModelName = 'model_name';
  static const String _keyModelId = 'model_id';
  static const String _keyModelUrl = 'model_url';
  static const String _keyModelFileName = 'model_file_name';
  static const String _keyHfToken = 'hf_token';
  static const String _keyAutoStart = 'auto_start';

  const AppConfigRepository({
    required this.defaultModelName,
    required this.defaultModelId,
    required this.defaultModelUrl,
    required this.defaultModelFileName,
    required this.defaultHfToken,
  });

  final String defaultModelName;
  final String defaultModelId;
  final String defaultModelUrl;
  final String defaultModelFileName;
  final String defaultHfToken;

  Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();

    return AppConfig(
      modelName: prefs.getString(_keyModelName) ?? defaultModelName,
      modelId: prefs.getString(_keyModelId) ?? defaultModelId,
      modelUrl: prefs.getString(_keyModelUrl) ?? defaultModelUrl,
      modelFileName: prefs.getString(_keyModelFileName) ?? defaultModelFileName,
      hfToken: prefs.getString(_keyHfToken) ?? defaultHfToken,
      autoStart: prefs.getBool(_keyAutoStart) ?? true,
    );
  }

  Future<void> save(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyModelName, config.modelName);
    await prefs.setString(_keyModelId, config.modelId);
    await prefs.setString(_keyModelUrl, config.modelUrl);
    await prefs.setString(_keyModelFileName, config.modelFileName);
    await prefs.setString(_keyHfToken, config.hfToken);
    await prefs.setBool(_keyAutoStart, config.autoStart);
  }
}
