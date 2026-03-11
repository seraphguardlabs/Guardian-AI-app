import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/api_service.dart';
import '../utils/preferences_manager.dart';
import 'vault_trash_screen.dart';

// ─── Constants ───────────────────────────────────────────────
const _kBgDark = Color(0xFF0D0D1A);
const _kCardDark = Color(0xFF1A1A2E);
const _kDialogBg = Color(0xFF1E1E2C);
const _kAccent = Color(0xFF283C9A);
const _kAccentLight = Color(0xFF5B8DEF);

class DocumentVaultScreen extends StatefulWidget {
  final String childHash;
  final String childName;

  const DocumentVaultScreen({
    super.key,
    required this.childHash,
    required this.childName,
  });

  @override
  State<DocumentVaultScreen> createState() => _DocumentVaultScreenState();
}

class _DocumentVaultScreenState extends State<DocumentVaultScreen> {
  bool _loading = true;
  bool _uploading = false;
  List<Map<String, dynamic>> _documents = [];
  List<Map<String, dynamic>> _folders = [];
  int? _currentFolderId;
  String? _currentFolderName;
  List<Map<String, dynamic>> _breadcrumbs = [];

  // Quota
  Map<String, dynamic>? _quota;

  // Search
  bool _isSearching = false;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchDocResults = [];
  List<Map<String, dynamic>> _searchFolderResults = [];

  @override
  void initState() {
    super.initState();
    _loadDocuments();
    _loadQuota();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─── Auth helpers ────────────────────────────────────────────
  String get _email =>
      Provider.of<PreferencesManager>(context, listen: false).getParentEmail() ?? '';
  String get _password =>
      Provider.of<PreferencesManager>(context, listen: false).getParentPassword() ?? '';
  ApiService get _api => Provider.of<ApiService>(context, listen: false);

  // ─── Data loading ────────────────────────────────────────────
  Future<void> _loadDocuments() async {
    setState(() => _loading = true);

    if (_currentFolderId != null) {
      final folderResult = await _api.getVaultFolderDetails(
        email: _email,
        password: _password,
        folderId: _currentFolderId!,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (folderResult['success'] == true) {
          final data = folderResult['data'] as Map<String, dynamic>;
          _folders = List<Map<String, dynamic>>.from(data['subfolders'] ?? []);
          _documents = List<Map<String, dynamic>>.from(data['documents'] ?? []);
          _breadcrumbs = List<Map<String, dynamic>>.from(data['breadcrumb'] ?? []);
          final folder = data['folder'] as Map<String, dynamic>?;
          _currentFolderName = folder?['name'] as String?;
        }
      });
    } else {
      final folderResult = await _api.listVaultFolders(
        email: _email,
        password: _password,
        childHash: widget.childHash,
      );
      final docResult = await _api.listVaultDocuments(
        email: _email,
        password: _password,
        childHash: widget.childHash,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _breadcrumbs = [];
        if (folderResult['success'] == true) {
          final data = folderResult['data'] as Map<String, dynamic>;
          _folders = List<Map<String, dynamic>>.from(data['folders'] ?? []);
        }
        if (docResult['success'] == true) {
          final data = docResult['data'] as Map<String, dynamic>;
          _documents = List<Map<String, dynamic>>.from(data['documents'] ?? []);
        }
      });
    }
  }

  Future<void> _loadQuota() async {
    final result = await _api.getVaultQuota(email: _email, password: _password);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _quota = (result['data'] as Map<String, dynamic>)['quota'] as Map<String, dynamic>?;
      });
    }
  }

  // ─── Search ──────────────────────────────────────────────────
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchDocResults = [];
        _searchFolderResults = [];
      });
      return;
    }

    final result = await _api.searchVault(
      email: _email,
      password: _password,
      query: query.trim(),
    );
    if (!mounted) return;
    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>;
      setState(() {
        _searchDocResults = List<Map<String, dynamic>>.from(data['documents'] ?? []);
        _searchFolderResults = List<Map<String, dynamic>>.from(data['folders'] ?? []);
      });
    }
  }

  // ─── Upload file ─────────────────────────────────────────────
  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp',
        'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
        'txt', 'csv', 'rtf',
        'mp3', 'wav', 'ogg', 'aac', 'flac', 'm4a',
        'mp4', 'mov', 'avi', 'mkv', 'webm',
        'zip', 'rar', '7z',
      ],
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access the selected file')),
        );
      }
      return;
    }

    // Show rename dialog before uploading
    final nameWithoutExt = file.name.contains('.')
        ? file.name.substring(0, file.name.lastIndexOf('.'))
        : file.name;
    final ext = file.name.contains('.')
        ? file.name.substring(file.name.lastIndexOf('.'))
        : '';

    final renameController = TextEditingController(text: nameWithoutExt);
    final displayName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        title: const Text('Rename File', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: renameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'File name',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                suffixText: ext,
                suffixStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.blueAccent),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = renameController.text.trim();
              Navigator.pop(ctx, name.isEmpty ? nameWithoutExt : name);
            },
            child: const Text('Upload'),
          ),
        ],
      ),
    );

    if (displayName == null) return;

    setState(() => _uploading = true);

    final uploadResult = await _api.uploadVaultDocument(
      email: _email,
      password: _password,
      filePath: file.path!,
      fileName: file.name,
      displayName: '$displayName$ext',
      folderId: _currentFolderId,
      childHash: widget.childHash,
    );

    if (!mounted) return;

    setState(() => _uploading = false);

    if (uploadResult['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$displayName$ext uploaded successfully')),
      );
      _loadDocuments();
      _loadQuota();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: ${uploadResult['error']}')),
      );
    }
  }

  // ─── Delete document (soft by default) ───────────────────────
  Future<void> _deleteDocument(int documentId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        title: const Text('Delete Document', style: TextStyle(color: Colors.white)),
        content: Text('Move "$name" to trash?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Move to Trash', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await _api.deleteVaultDocument(
      email: _email,
      password: _password,
      documentId: documentId,
    );

    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document moved to trash')),
      );
      _loadDocuments();
      _loadQuota();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${result['error']}')),
      );
    }
  }

  // ─── Star / Unstar document ──────────────────────────────────
  Future<void> _toggleStarDocument(int documentId, bool currentlyStarred) async {
    final result = await _api.updateVaultDocument(
      email: _email,
      password: _password,
      documentId: documentId,
      isStarred: !currentlyStarred,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      _loadDocuments();
    }
  }

  // ─── Document details bottom sheet ───────────────────────────
  Future<void> _showDocumentDetails(int documentId) async {
    final result = await _api.getVaultDocumentDetails(
      email: _email,
      password: _password,
      documentId: documentId,
    );
    if (!mounted) return;
    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${result['error']}')),
      );
      return;
    }

    final doc = (result['data'] as Map<String, dynamic>)['document'] as Map<String, dynamic>;
    final name = doc['display_name'] ?? doc['name'] ?? 'Unknown';
    final originalName = doc['original_filename'] ?? '';
    final size = doc['formatted_size'] ?? '';
    final category = doc['file_category'] ?? '';
    final mime = doc['mime_type'] ?? '';
    final description = doc['description'] ?? '';
    final tags = List<String>.from(doc['tags'] ?? []);
    final isStarred = doc['is_starred'] == true;
    final accessCount = doc['access_count'] ?? 0;
    final createdAt = doc['created_at'] as String?;
    final docId = doc['id'] as int;

    String dateStr = '';
    if (createdAt != null) {
      try {
        dateStr = DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(createdAt));
      } catch (_) {}
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: _kDialogBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(_iconForCategory(category), color: _colorForCategory(category), size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(name,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  icon: Icon(isStarred ? Icons.star : Icons.star_border,
                      color: isStarred ? Colors.amber : Colors.white38),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _toggleStarDocument(docId, isStarred);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _detailRow('Original name', originalName),
            _detailRow('Size', size),
            _detailRow('Type', '$category ($mime)'),
            if (description.isNotEmpty) _detailRow('Description', description),
            if (dateStr.isNotEmpty) _detailRow('Uploaded', dateStr),
            _detailRow('Views', '$accessCount'),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: tags.map((t) => Chip(
                  label: Text(t, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  backgroundColor: _kAccent.withOpacity(0.3),
                  side: BorderSide.none,
                )).toList(),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
                    icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                    label: const Text('Download', style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openDocument(docId, name);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: _kAccent.withOpacity(0.6)),
                    icon: const Icon(Icons.share, color: Colors.white, size: 18),
                    label: const Text('Share', style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showShareDialog(docId, name);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110,
            child: Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      ),
    );
  }

  // ─── Share link dialog ───────────────────────────────────────
  Future<void> _showShareDialog(int documentId, String name) async {
    final expiresController = TextEditingController(text: '24');
    final maxDlController = TextEditingController();
    final pwController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        title: Text('Share "$name"', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: expiresController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Expires in (hours)',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  hintText: 'Leave empty for no expiry',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: maxDlController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Max downloads',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  hintText: 'Leave empty for unlimited',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pwController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password (optional)',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create Link'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await _api.createVaultShareLink(
      email: _email,
      password: _password,
      documentId: documentId,
      expiresHours: int.tryParse(expiresController.text.trim()),
      maxDownloads: int.tryParse(maxDlController.text.trim()),
      linkPassword: pwController.text.trim().isEmpty ? null : pwController.text.trim(),
    );

    if (!mounted) return;
    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>;
      final shareLink = data['share_link'] as Map<String, dynamic>?;
      final url = shareLink?['url'] as String? ?? '';
      final fullUrl = 'https://seraphguardlabs.com$url';

      await Clipboard.setData(ClipboardData(text: fullUrl));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Share link copied to clipboard!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${result['error']}')),
      );
    }
  }

  // ─── Folder management ───────────────────────────────────────
  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    final folderName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        title: const Text('New Folder', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blueAccent),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (folderName == null || folderName.isEmpty) return;

    final result = await _api.createVaultFolder(
      email: _email,
      password: _password,
      name: folderName,
      childHash: widget.childHash,
    );

    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Folder "$folderName" created')),
      );
      _loadDocuments();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${result['error']}')),
      );
    }
  }

  Future<void> _showRenameFolderDialog(int folderId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        title: const Text('Rename Folder', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blueAccent),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == currentName) return;

    final result = await _api.updateVaultFolder(
      email: _email,
      password: _password,
      folderId: folderId,
      name: newName,
    );

    if (!mounted) return;
    if (result['success'] == true) {
      _loadDocuments();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rename failed: ${result['error']}')),
      );
    }
  }

  Future<void> _deleteFolder(int folderId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        title: const Text('Delete Folder', style: TextStyle(color: Colors.white)),
        content: Text(
          'Permanently delete "$name" and all its contents?\nThis cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await _api.deleteVaultFolder(
      email: _email,
      password: _password,
      folderId: folderId,
    );

    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Folder "$name" deleted')),
      );
      _loadDocuments();
      _loadQuota();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${result['error']}')),
      );
    }
  }

  void _openFolder(Map<String, dynamic> folder) {
    setState(() {
      _currentFolderId = folder['id'] as int?;
      _currentFolderName = folder['name'] as String?;
    });
    _loadDocuments();
  }

  void _navigateToBreadcrumb(int? folderId) {
    setState(() {
      _currentFolderId = folderId;
      _currentFolderName = null;
    });
    _loadDocuments();
  }

  void _goBack() {
    if (_breadcrumbs.length > 1) {
      final parent = _breadcrumbs[_breadcrumbs.length - 2];
      _navigateToBreadcrumb(parent['id'] as int?);
    } else {
      _navigateToBreadcrumb(null);
    }
  }

  // ─── Download & Open ─────────────────────────────────────────
  Future<void> _openDocument(int documentId, String name) async {
    final progressNotifier = ValueNotifier<double>(-1.0);
    bool cancelled = false;
    final cancelToken = CancelToken();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        title: const Text('Downloading...', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: value >= 0 ? value : null,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(_kAccentLight),
              ),
              const SizedBox(height: 12),
              Text(
                value >= 0 ? '${(value * 100).toStringAsFixed(0)}%' : 'Preparing...',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              cancelToken.cancel('User cancelled');
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    final result = await _api.getVaultDocumentDownloadUrl(
      email: _email,
      password: _password,
      documentId: documentId,
    );

    if (!mounted || cancelled) {
      progressNotifier.dispose();
      return;
    }

    if (result['success'] != true) {
      Navigator.of(context).pop();
      progressNotifier.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get file: ${result['error']}')),
      );
      return;
    }

    final data = result['data'] as Map<String, dynamic>;
    final downloadUrl = data['download_url'] as String?;

    if (downloadUrl == null || downloadUrl.isEmpty) {
      Navigator.of(context).pop();
      progressNotifier.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No download URL available')),
      );
      return;
    }

    final fullUrl = downloadUrl.startsWith('http')
        ? downloadUrl
        : 'https://seraphguardlabs.com$downloadUrl';

    try {
      final dir = await getApplicationDocumentsDirectory();
      final sanitizedName = name.replaceAll(RegExp(r'[^a-zA-Z0-9._\-]'), '_');
      final filePath = '${dir.path}/vault_downloads/$sanitizedName';

      final downloadDir = Directory('${dir.path}/vault_downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final dio = Dio();
      await dio.download(
        fullUrl,
        filePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && !cancelled) {
            progressNotifier.value = received / total;
          }
        },
      );

      if (!mounted || cancelled) {
        progressNotifier.dispose();
        return;
      }

      Navigator.of(context).pop();
      progressNotifier.dispose();

      final openResult = await OpenFilex.open(filePath);
      if (openResult.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: ${openResult.message}')),
        );
      }
    } catch (e) {
      progressNotifier.dispose();
      if (!mounted) return;
      if (!cancelled) Navigator.of(context).pop();
      if (e is DioException && e.type == DioExceptionType.cancel) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────
  IconData _iconForCategory(String? category) {
    switch (category) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'image':
        return Icons.image;
      case 'document':
        return Icons.description;
      case 'spreadsheet':
        return Icons.table_chart;
      case 'audio':
        return Icons.audio_file;
      case 'video':
        return Icons.video_file;
      case 'archive':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _colorForCategory(String? category) {
    switch (category) {
      case 'pdf':
        return Colors.redAccent;
      case 'image':
        return Colors.greenAccent;
      case 'document':
        return Colors.blueAccent;
      case 'spreadsheet':
        return Colors.orangeAccent;
      case 'audio':
        return Colors.purpleAccent;
      case 'video':
        return Colors.tealAccent;
      case 'archive':
        return Colors.brown;
      default:
        return Colors.grey;
    }
  }

  // ─── Build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgDark,
      appBar: _buildAppBar(),
      floatingActionButton: _isSearching
          ? null
          : FloatingActionButton.extended(
              backgroundColor: _kAccent,
              onPressed: _uploading ? null : _pickAndUploadFile,
              icon: _uploading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.upload_file, color: Colors.white),
              label: Text(
                _uploading ? 'Uploading...' : 'Upload',
                style: const TextStyle(color: Colors.white),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadDocuments();
                await _loadQuota();
              },
              child: _isSearching ? _buildSearchResults() : _buildContent(),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_isSearching) {
      return AppBar(
        backgroundColor: _kBgDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            setState(() {
              _isSearching = false;
              _searchController.clear();
              _searchDocResults = [];
              _searchFolderResults = [];
            });
          },
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search documents & folders...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
            border: InputBorder.none,
          ),
          onSubmitted: _performSearch,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => _performSearch(_searchController.text),
          ),
        ],
      );
    }

    return AppBar(
      backgroundColor: _kBgDark,
      elevation: 0,
      title: Text(
        _currentFolderName ?? '${widget.childName}\'s Documents',
        style: const TextStyle(color: Colors.white, fontSize: 18),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () {
          if (_currentFolderId != null) {
            _goBack();
          } else {
            Navigator.pop(context);
          }
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search, color: Colors.white),
          tooltip: 'Search',
          onPressed: () => setState(() => _isSearching = true),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          color: _kDialogBg,
          onSelected: (value) {
            switch (value) {
              case 'new_folder':
                _showCreateFolderDialog();
                break;
              case 'trash':
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VaultTrashScreen()),
                ).then((_) {
                  _loadDocuments();
                  _loadQuota();
                });
                break;
              case 'quota':
                _showQuotaDialog();
                break;
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'new_folder',
              child: Row(children: [
                Icon(Icons.create_new_folder_outlined, color: Colors.white70, size: 20),
                SizedBox(width: 10),
                Text('New Folder', style: TextStyle(color: Colors.white)),
              ]),
            ),
            const PopupMenuItem(
              value: 'trash',
              child: Row(children: [
                Icon(Icons.delete_outline, color: Colors.white70, size: 20),
                SizedBox(width: 10),
                Text('Trash', style: TextStyle(color: Colors.white)),
              ]),
            ),
            const PopupMenuItem(
              value: 'quota',
              child: Row(children: [
                Icon(Icons.storage, color: Colors.white70, size: 20),
                SizedBox(width: 10),
                Text('Storage', style: TextStyle(color: Colors.white)),
              ]),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: () {
            _loadDocuments();
            _loadQuota();
          },
        ),
      ],
    );
  }

  // ─── Quota dialog ────────────────────────────────────────────
  void _showQuotaDialog() {
    final q = _quota;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        title: const Text('Storage Usage', style: TextStyle(color: Colors.white)),
        content: q == null
            ? const Text('Loading...', style: TextStyle(color: Colors.white70))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: ((q['percentage_used'] as num?) ?? 0) / 100,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(_kAccentLight),
                  ),
                  const SizedBox(height: 12),
                  _detailRow('Used', '${q['formatted_used'] ?? '?'} of ${q['formatted_max'] ?? '?'}'),
                  _detailRow('Remaining', q['formatted_remaining'] ?? '?'),
                  _detailRow('Files', '${q['current_file_count'] ?? 0} / ${q['max_file_count'] ?? 1000}'),
                ],
              ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  // ─── Breadcrumb bar ──────────────────────────────────────────
  Widget _buildBreadcrumbs() {
    if (_breadcrumbs.isEmpty && _currentFolderId == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _navigateToBreadcrumb(null),
              child: Text('Root',
                style: TextStyle(color: _kAccentLight, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            for (int i = 0; i < _breadcrumbs.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.chevron_right, size: 16, color: Colors.white.withOpacity(0.3)),
              ),
              GestureDetector(
                onTap: i < _breadcrumbs.length - 1
                    ? () => _navigateToBreadcrumb(_breadcrumbs[i]['id'] as int?)
                    : null,
                child: Text(
                  _breadcrumbs[i]['name'] as String? ?? '',
                  style: TextStyle(
                    color: i < _breadcrumbs.length - 1 ? _kAccentLight : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Quota bar ───────────────────────────────────────────────
  Widget _buildQuotaBar() {
    if (_quota == null) return const SizedBox.shrink();
    final pct = ((_quota!['percentage_used'] as num?) ?? 0).toDouble();
    final used = _quota!['formatted_used'] ?? '?';
    final max = _quota!['formatted_max'] ?? '?';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                pct > 90 ? Colors.redAccent : _kAccentLight,
              ),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$used / $max',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
              Text('${pct.toStringAsFixed(1)}%',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Main content ────────────────────────────────────────────
  Widget _buildContent() {
    final hasContent = _folders.isNotEmpty || _documents.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        _buildQuotaBar(),
        _buildBreadcrumbs(),

        if (!hasContent)
          Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open, size: 64, color: Colors.white.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text(
                    _currentFolderId != null ? 'This folder is empty' : 'No documents yet',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap Upload to add a certificate or document',
                    style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else ...[
          if (_folders.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 8),
              child: Text('Folders',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6), fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            ..._folders.map(_buildFolderTile),
            const SizedBox(height: 8),
          ],
          if (_documents.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Text('Documents',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6), fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            ..._documents.map(_buildDocumentTile),
          ],
        ],
      ],
    );
  }

  // ─── Search results ──────────────────────────────────────────
  Widget _buildSearchResults() {
    final hasDocs = _searchDocResults.isNotEmpty;
    final hasFolders = _searchFolderResults.isNotEmpty;

    if (!hasDocs && !hasFolders) {
      return Center(
        child: Text(
          _searchController.text.isEmpty ? 'Type to search' : 'No results found',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (hasFolders) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Text('Folders',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6), fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          ..._searchFolderResults.map(_buildFolderTile),
          const SizedBox(height: 8),
        ],
        if (hasDocs) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Text('Documents',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6), fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          ..._searchDocResults.map(_buildDocumentTile),
        ],
      ],
    );
  }

  // ─── Folder tile ─────────────────────────────────────────────
  Widget _buildFolderTile(Map<String, dynamic> folder) {
    final name = folder['name'] ?? 'Untitled';
    final count = folder['document_count'] ?? 0;
    final size = folder['formatted_size'] ?? folder['total_size']?.toString() ?? '';
    final id = folder['id'] as int?;
    final color = folder['color'] as String?;
    final isStarred = folder['is_starred'] == true;

    Color folderColor = _kAccentLight;
    if (color != null && color.isNotEmpty) {
      try {
        folderColor = Color(int.parse(color.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: _kCardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: folderColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.folder, color: folderColor, size: 26),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              ),
              if (isStarred) const Icon(Icons.star, color: Colors.amber, size: 16),
            ],
          ),
          subtitle: Text(
            '$count document${count == 1 ? '' : 's'}${size.isNotEmpty ? ' · $size' : ''}',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
          ),
          trailing: id != null
              ? PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20),
                  color: _kDialogBg,
                  onSelected: (value) {
                    switch (value) {
                      case 'rename':
                        _showRenameFolderDialog(id, name);
                        break;
                      case 'delete':
                        _deleteFolder(id, name);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'rename',
                      child: Text('Rename', style: TextStyle(color: Colors.white)),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                )
              : const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: () => _openFolder(folder),
        ),
      ),
    );
  }

  // ─── Document tile ───────────────────────────────────────────
  Widget _buildDocumentTile(Map<String, dynamic> doc) {
    final name = doc['name'] ?? doc['original_filename'] ?? 'Unknown';
    final category = doc['file_category'] as String?;
    final size = doc['formatted_size'] ?? '';
    final id = doc['id'] as int?;
    final isStarred = doc['is_starred'] == true;
    final createdAt = doc['created_at'] as String?;

    String dateStr = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt);
        dateStr = DateFormat('MMM d, yyyy').format(dt);
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: _kCardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _colorForCategory(category).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_iconForCategory(category), color: _colorForCategory(category), size: 24),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (isStarred)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.star, color: Colors.amber, size: 16),
                ),
            ],
          ),
          subtitle: Text(
            [if (size.isNotEmpty) size, if (dateStr.isNotEmpty) dateStr].join(' · '),
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
          ),
          trailing: id != null
              ? PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20),
                  color: _kDialogBg,
                  onSelected: (value) {
                    switch (value) {
                      case 'download':
                        _openDocument(id, name);
                        break;
                      case 'details':
                        _showDocumentDetails(id);
                        break;
                      case 'star':
                        _toggleStarDocument(id, isStarred);
                        break;
                      case 'share':
                        _showShareDialog(id, name);
                        break;
                      case 'delete':
                        _deleteDocument(id, name);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'download',
                      child: Row(children: [
                        Icon(Icons.download_rounded, color: Colors.white70, size: 18),
                        SizedBox(width: 8),
                        Text('Download & Open', style: TextStyle(color: Colors.white)),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'details',
                      child: Row(children: [
                        Icon(Icons.info_outline, color: Colors.white70, size: 18),
                        SizedBox(width: 8),
                        Text('Details', style: TextStyle(color: Colors.white)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'star',
                      child: Row(children: [
                        Icon(isStarred ? Icons.star_border : Icons.star,
                            color: Colors.white70, size: 18),
                        const SizedBox(width: 8),
                        Text(isStarred ? 'Unstar' : 'Star',
                            style: const TextStyle(color: Colors.white)),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'share',
                      child: Row(children: [
                        Icon(Icons.share, color: Colors.white70, size: 18),
                        SizedBox(width: 8),
                        Text('Share Link', style: TextStyle(color: Colors.white)),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.redAccent)),
                      ]),
                    ),
                  ],
                )
              : null,
          onTap: id != null ? () => _openDocument(id, name) : null,
        ),
      ),
    );
  }
}
