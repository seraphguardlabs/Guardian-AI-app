import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ModelRepository {
  ModelRepository({
    required this.modelId,
    required this.modelUrl,
    required this.modelFileName,
    this.hfToken,
  });

  final String modelId;
  final String modelUrl;
  final String modelFileName;
  final String? hfToken;

  Future<String> ensureModelAvailable({
    void Function(double progress)? onProgress,
  }) async {
    if (modelUrl.contains('example.com')) {
      throw Exception('Set GEMMA4_MODEL_URL to your downloadable $_safeModelId artifact URL.');
    }

    final token = hfToken?.trim() ?? '';

    final appSupportDir = await getApplicationSupportDirectory();
    final modelDir = Directory(
      '${appSupportDir.path}${Platform.pathSeparator}models${Platform.pathSeparator}$_safeModelId',
    );
    if (!modelDir.existsSync()) {
      modelDir.createSync(recursive: true);
    }

    final file = File('${modelDir.path}${Platform.pathSeparator}$modelFileName');
    if (file.existsSync() && file.lengthSync() > 0) {
      onProgress?.call(1.0);
      return file.path;
    }

    final request = http.Request('GET', Uri.parse(modelUrl));
    if (token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final streamed = await request.send();

    if (streamed.statusCode != 200) {
      if ((streamed.statusCode == 401 || streamed.statusCode == 403) && token.isEmpty) {
        throw Exception(
          'Model download is access-restricted. Provide HF token in app setup and retry.',
        );
      }
      throw Exception('Model download failed with status ${streamed.statusCode}.');
    }

    final totalBytes = streamed.contentLength ?? 0;
    var downloaded = 0;

    final tempFile = File('${file.path}.download');
    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }

    final sink = tempFile.openWrite();
    try {
      await for (final chunk in streamed.stream) {
        downloaded += chunk.length;
        sink.add(chunk);
        if (totalBytes > 0) {
          onProgress?.call(downloaded / totalBytes);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (file.existsSync()) {
      file.deleteSync();
    }
    tempFile.renameSync(file.path);

    onProgress?.call(1.0);
    return file.path;
  }

  String get _safeModelId => modelId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
}
