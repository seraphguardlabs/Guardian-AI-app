import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../services/document_vault_service.dart';
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
  final _vaultService = DocumentVaultService();
  bool _loading = true;
  bool _importing = false;
  List<Map<String, dynamic>> _documents = [];
  List<Map<String, dynamic>> _folders = [];
  int? _currentFolderId;
  String? _currentFolderName;
  List<Map<String, dynamic>> _breadcrumbs = [];
  Map<String, dynamic>? _stats;
  bool _isSearching = false;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchDocResults = [];
  List<Map<String, dynamic>> _searchFolderResults = [];
  bool _gridView = false;
  String _sortBy = 'name';

  @override
  void initState() {
    super.initState();
    _initVault();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initVault() async {
    await _vaultService.ensurePresetFolders(childHash: widget.childHash);
    await _loadContent();
    await _loadStats();
  }

  Future<void> _loadContent() async {
    setState(() => _loading = true);
    try {
      if (_currentFolderId != null) {
        final details = await _vaultService.getFolderDetails(folderId: _currentFolderId!);
        if (!mounted) return;
        setState(() {
          _loading = false;
          _folders = List<Map<String, dynamic>>.from(details['subfolders'] ?? []);
          _documents = List<Map<String, dynamic>>.from(details['documents'] ?? []);
          _breadcrumbs = List<Map<String, dynamic>>.from(details['breadcrumb'] ?? []);
          final folder = details['folder'] as Map<String, dynamic>?;
          _currentFolderName = folder?['name'] as String?;
        });
      } else {
        final folders = await _vaultService.listFolders(childHash: widget.childHash);
        final docs = await _vaultService.listDocuments(childHash: widget.childHash);
        if (!mounted) return;
        setState(() {
          _loading = false;
          _folders = folders;
          _documents = docs;
          _breadcrumbs = [];
          _currentFolderName = null;
        });
      }
      _sortContent();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Failed to load: $e');
    }
  }

  Future<void> _loadStats() async {
    final stats = await _vaultService.getStorageStats(childHash: widget.childHash);
    if (mounted) setState(() => _stats = stats);
  }

  void _sortContent() {
    setState(() {
      switch (_sortBy) {
        case 'name':
          _folders.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
          _documents.sort((a, b) => (a['display_name'] as String).compareTo(b['display_name'] as String));
          break;
        case 'date':
          _documents.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
          break;
        case 'size':
          _documents.sort((a, b) => ((b['file_size'] as int?) ?? 0).compareTo((a['file_size'] as int?) ?? 0));
          break;
      }
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _searchDocResults = []; _searchFolderResults = []; });
      return;
    }
    final results = await _vaultService.search(childHash: widget.childHash, query: query.trim());
    if (!mounted) return;
    setState(() {
      _searchDocResults = results['documents'] ?? [];
      _searchFolderResults = results['folders'] ?? [];
    });
  }

  // ─── Import file ─────────────────────────────────────────────
  Future<void> _pickAndImportFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
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

    if (result.files.length == 1) {
      final file = result.files.first;
      if (file.path == null) { _showError('Could not access the selected file'); return; }
      await _importSingleFile(file);
    } else {
      setState(() => _importing = true);
      int successCount = 0;
      for (final file in result.files) {
        if (file.path == null) continue;
        try {
          await _vaultService.addDocument(
            sourcePath: file.path!,
            displayName: file.name,
            originalFilename: file.name,
            childHash: widget.childHash,
            folderId: _currentFolderId,
          );
          successCount++;
        } catch (e) { debugPrint('Failed to import ${file.name}: $e'); }
      }
      if (!mounted) return;
      setState(() => _importing = false);
      _showSnack('$successCount file(s) imported successfully');
      _loadContent();
      _loadStats();
    }
  }

  Future<void> _importSingleFile(PlatformFile file) async {
    final nameWithoutExt = file.name.contains('.')
        ? file.name.substring(0, file.name.lastIndexOf('.')) : file.name;
    final ext = file.name.contains('.')
        ? file.name.substring(file.name.lastIndexOf('.')) : '';

    final renameController = TextEditingController(text: nameWithoutExt);
    final descController = TextEditingController();
    final tagsController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Import File', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(_iconForCategory(detectFileCategory(file.name)),
                      color: _colorForCategory(detectFileCategory(file.name)), size: 28),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(file.name, style: const TextStyle(color: Colors.white70, fontSize: 12),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(formatFileSize(file.size),
                          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                    ],
                  )),
                ]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: renameController, autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Display Name',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  suffixText: ext,
                  suffixStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kAccentLight)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                style: const TextStyle(color: Colors.white), maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kAccentLight)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagsController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Tags (comma separated)',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  hintText: 'e.g. report, 2026, important',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kAccentLight)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _importing = true);
    try {
      final displayName = renameController.text.trim().isEmpty ? nameWithoutExt : renameController.text.trim();
      final tags = tagsController.text.trim().isEmpty ? <String>[]
          : tagsController.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      await _vaultService.addDocument(
        sourcePath: file.path!,
        displayName: '$displayName$ext',
        originalFilename: file.name,
        childHash: widget.childHash,
        folderId: _currentFolderId,
        description: descController.text.trim(),
        tags: tags,
      );
      if (!mounted) return;
      setState(() => _importing = false);
      _showSnack('$displayName$ext imported successfully');
      _loadContent();
      _loadStats();
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      _showError('Import failed: $e');
    }
  }

  // ─── Document actions ────────────────────────────────────────
  Future<void> _deleteDocument(int documentId, String name) async {
    final confirmed = await _confirmDialog(
      title: 'Delete Document', message: 'Move "$name" to trash?',
      confirmText: 'Move to Trash', confirmColor: Colors.redAccent,
    );
    if (!confirmed) return;
    await _vaultService.softDeleteDocument(documentId: documentId);
    if (!mounted) return;
    _showSnack('Document moved to trash');
    _loadContent();
    _loadStats();
  }

  Future<void> _toggleStarDocument(int documentId, bool currentlyStarred) async {
    await _vaultService.updateDocument(documentId: documentId, isStarred: !currentlyStarred);
    if (mounted) _loadContent();
  }

  Future<void> _renameDocument(int documentId, String currentName) async {
    final ext = currentName.contains('.') ? currentName.substring(currentName.lastIndexOf('.')) : '';
    final nameNoExt = currentName.contains('.') ? currentName.substring(0, currentName.lastIndexOf('.')) : currentName;
    final controller = TextEditingController(text: nameNoExt);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename Document', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            suffixText: ext, suffixStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kAccentLight)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == nameNoExt) return;
    await _vaultService.updateDocument(documentId: documentId, displayName: '$newName$ext');
    if (mounted) _loadContent();
  }

  Future<void> _moveDocument(int documentId, String name) async {
    final allFolders = await _vaultService.listFolders(childHash: widget.childHash);
    if (!mounted) return;
    int? selectedFolderId;
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => AlertDialog(
          backgroundColor: _kDialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Move "$name"', style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RadioListTile<int?>(
                value: null, groupValue: selectedFolderId,
                title: const Text('Root (No folder)', style: TextStyle(color: Colors.white)),
                activeColor: _kAccentLight,
                onChanged: (v) => setDialogState(() => selectedFolderId = v),
              ),
              const Divider(color: Colors.white12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true, itemCount: allFolders.length,
                  itemBuilder: (_, i) {
                    final f = allFolders[i];
                    final fId = f['id'] as int;
                    return RadioListTile<int?>(
                      value: fId, groupValue: selectedFolderId,
                      title: Text(f['name'] as String, style: const TextStyle(color: Colors.white)),
                      secondary: Icon(_iconForFolderType(f['folder_type'] as String? ?? 'custom'),
                          color: _parseFolderColor(f['color'] as String?), size: 22),
                      activeColor: _kAccentLight,
                      onChanged: (v) => setDialogState(() => selectedFolderId = v),
                    );
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6)))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () => Navigator.pop(ctx, selectedFolderId ?? -1),
              child: const Text('Move', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final targetId = result == -1 ? null : result;
    await _vaultService.moveDocument(documentId: documentId, folderId: targetId);
    if (mounted) {
      _showSnack('Moved to ${targetId == null ? "Root" : "folder"}');
      _loadContent();
    }
  }

  Future<void> _showDocumentDetails(int documentId) async {
    final doc = await _vaultService.getDocumentDetails(documentId: documentId);
    if (doc == null || !mounted) return;
    final name = doc['display_name'] ?? doc['original_filename'] ?? 'Unknown';
    final originalName = doc['original_filename'] ?? '';
    final formattedSize = doc['formatted_size'] ?? '';
    final category = doc['file_category'] ?? '';
    final mime = doc['mime_type'] ?? '';
    final description = (doc['description'] as String?) ?? '';
    final tags = doc['tags'] is List ? List<String>.from(doc['tags']) : <String>[];
    final isStarred = doc['is_starred'] == 1;
    final accessCount = doc['access_count'] ?? 0;
    final createdAt = doc['created_at'] as String?;
    final docId = doc['id'] as int;
    String dateStr = '';
    if (createdAt != null) {
      try { dateStr = DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(createdAt)); } catch (_) {}
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context, backgroundColor: _kDialogBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.55, maxChildSize: 0.85,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl, padding: const EdgeInsets.all(20),
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Icon(_iconForCategory(category), color: _colorForCategory(category), size: 32),
              const SizedBox(width: 12),
              Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
              IconButton(
                icon: Icon(isStarred ? Icons.star : Icons.star_border,
                    color: isStarred ? Colors.amber : Colors.white38),
                onPressed: () { Navigator.pop(ctx); _toggleStarDocument(docId, isStarred); },
              ),
            ]),
            const SizedBox(height: 16),
            _detailRow('Original name', originalName),
            _detailRow('Size', formattedSize),
            _detailRow('Type', '$category ($mime)'),
            if (description.isNotEmpty) _detailRow('Description', description),
            if (dateStr.isNotEmpty) _detailRow('Added', dateStr),
            _detailRow('Opens', '$accessCount'),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4,
                children: tags.map((t) => Chip(
                  label: Text(t, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  backgroundColor: _kAccent.withOpacity(0.3), side: BorderSide.none,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )).toList()),
            ],
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _kAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                icon: const Icon(Icons.open_in_new, color: Colors.white, size: 18),
                label: const Text('Open', style: TextStyle(color: Colors.white)),
                onPressed: () { Navigator.pop(ctx); _openDocument(docId, name); },
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _kAccent.withOpacity(0.6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                icon: const Icon(Icons.drive_file_move_outlined, color: Colors.white, size: 18),
                label: const Text('Move', style: TextStyle(color: Colors.white)),
                onPressed: () { Navigator.pop(ctx); _moveDocument(docId, name); },
              )),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(label,
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13))),
        Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13))),
      ]),
    );
  }

  Future<void> _openDocument(int documentId, String name) async {
    final filePath = await _vaultService.getDocumentFilePath(documentId: documentId);
    if (filePath == null) { if (mounted) _showError('File not found on device'); return; }
    await _vaultService.trackAccess(documentId: documentId);
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done && mounted) {
      _showError('Could not open file: ${result.message}');
    }
  }

  // ─── Folder management ───────────────────────────────────────
  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    String selectedType = 'custom';
    String selectedColor = '#5B8DEF';
    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => AlertDialog(
          backgroundColor: _kDialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('New Folder', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller, autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Folder Name',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kAccentLight)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Folder Type', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8,
                children: VaultFolderType.presets.map((type) {
                  final isSelected = selectedType == type.key;
                  return GestureDetector(
                    onTap: () {
                      setDialogState(() {
                        selectedType = type.key;
                        selectedColor = type.color;
                        if (controller.text.isEmpty || VaultFolderType.presets.any((p) => p.label == controller.text)) {
                          controller.text = type.label;
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? _parseFolderColor(type.color).withOpacity(0.3) : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected ? Border.all(color: _parseFolderColor(type.color), width: 1.5) : null,
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_iconForFolderType(type.key), size: 16, color: _parseFolderColor(type.color)),
                        const SizedBox(width: 6),
                        Text(type.label, style: TextStyle(color: Colors.white.withOpacity(isSelected ? 1 : 0.6), fontSize: 12)),
                      ]),
                    ),
                  );
                }).toList()),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6)))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx, {'name': name, 'type': selectedType, 'color': selectedColor});
              },
              child: const Text('Create', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _vaultService.createFolder(
      name: result['name']!, childHash: widget.childHash,
      parentId: _currentFolderId, folderType: result['type']!, color: result['color'],
    );
    if (!mounted) return;
    _showSnack('Folder "${result['name']}" created');
    _loadContent();
    _loadStats();
  }

  Future<void> _showRenameFolderDialog(int folderId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename Folder', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kAccentLight)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == currentName) return;
    await _vaultService.updateFolder(folderId: folderId, name: newName);
    if (mounted) _loadContent();
  }

  Future<void> _deleteFolder(int folderId, String name) async {
    final confirmed = await _confirmDialog(
      title: 'Delete Folder',
      message: 'Permanently delete "$name" and all its contents?\nThis cannot be undone.',
      confirmText: 'Delete', confirmColor: Colors.redAccent,
    );
    if (!confirmed) return;
    await _vaultService.deleteFolder(folderId: folderId);
    if (!mounted) return;
    _showSnack('Folder "$name" deleted');
    _loadContent();
    _loadStats();
  }

  void _openFolder(Map<String, dynamic> folder) {
    setState(() {
      _currentFolderId = folder['id'] as int?;
      _currentFolderName = folder['name'] as String?;
    });
    _loadContent();
  }

  void _navigateToBreadcrumb(int? folderId) {
    setState(() { _currentFolderId = folderId; _currentFolderName = null; });
    _loadContent();
  }

  void _goBack() {
    if (_breadcrumbs.length > 1) {
      _navigateToBreadcrumb(_breadcrumbs[_breadcrumbs.length - 2]['id'] as int?);
    } else {
      _navigateToBreadcrumb(null);
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────
  IconData _iconForCategory(String? category) {
    switch (category) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'image': return Icons.image;
      case 'document': return Icons.description;
      case 'spreadsheet': return Icons.table_chart;
      case 'presentation': return Icons.slideshow;
      case 'audio': return Icons.audio_file;
      case 'video': return Icons.video_file;
      case 'archive': return Icons.folder_zip;
      default: return Icons.insert_drive_file;
    }
  }

  Color _colorForCategory(String? category) {
    switch (category) {
      case 'pdf': return Colors.redAccent;
      case 'image': return Colors.greenAccent;
      case 'document': return Colors.blueAccent;
      case 'spreadsheet': return Colors.orangeAccent;
      case 'presentation': return Colors.deepOrangeAccent;
      case 'audio': return Colors.purpleAccent;
      case 'video': return Colors.tealAccent;
      case 'archive': return Colors.brown;
      default: return Colors.grey;
    }
  }

  IconData _iconForFolderType(String type) {
    switch (type) {
      case 'medical': return Icons.medical_services;
      case 'school': return Icons.school;
      case 'legal': return Icons.gavel;
      case 'photos': return Icons.photo_library;
      case 'certificates': return Icons.workspace_premium;
      case 'financial': return Icons.account_balance;
      case 'ids': return Icons.badge;
      case 'insurance': return Icons.health_and_safety;
      case 'emergency': return Icons.emergency;
      default: return Icons.folder;
    }
  }

  Color _parseFolderColor(String? hex) {
    if (hex == null || hex.isEmpty) return _kAccentLight;
    try { return Color(int.parse(hex.replaceFirst('#', '0xFF'))); } catch (_) { return _kAccentLight; }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message), behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message), backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<bool> _confirmDialog({
    required String title, required String message,
    required String confirmText, Color confirmColor = _kAccentLight,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmText, style: TextStyle(color: confirmColor))),
        ],
      ),
    );
    return result == true;
  }

  // ─── Build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentFolderId == null && !_isSearching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSearching) {
          setState(() { _isSearching = false; _searchController.clear(); _searchDocResults = []; _searchFolderResults = []; });
        } else if (_currentFolderId != null) {
          _goBack();
        }
      },
      child: Scaffold(
        backgroundColor: _kBgDark,
        appBar: _buildAppBar(),
        floatingActionButton: _isSearching ? null : _buildFab(),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _kAccentLight))
            : RefreshIndicator(
                onRefresh: () async { await _loadContent(); await _loadStats(); },
                child: _isSearching ? _buildSearchResults() : _buildContent(),
              ),
      ),
    );
  }

  Widget _buildFab() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      FloatingActionButton.small(
        heroTag: 'new_folder', backgroundColor: _kCardDark,
        onPressed: _showCreateFolderDialog,
        child: const Icon(Icons.create_new_folder_outlined, color: _kAccentLight, size: 20),
      ),
      const SizedBox(height: 10),
      FloatingActionButton.extended(
        heroTag: 'import_file', backgroundColor: _kAccent,
        onPressed: _importing ? null : _pickAndImportFile,
        icon: _importing
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add, color: Colors.white),
        label: Text(_importing ? 'Importing...' : 'Import File',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    ]);
  }

  PreferredSizeWidget _buildAppBar() {
    if (_isSearching) {
      return AppBar(
        backgroundColor: _kBgDark, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => setState(() { _isSearching = false; _searchController.clear(); _searchDocResults = []; _searchFolderResults = []; })),
        title: TextField(
          controller: _searchController, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(hintText: 'Search documents & folders...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)), border: InputBorder.none),
          onChanged: _performSearch,
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(icon: const Icon(Icons.clear, color: Colors.white54),
              onPressed: () { _searchController.clear(); _performSearch(''); }),
        ],
      );
    }
    return AppBar(
      backgroundColor: _kBgDark, elevation: 0,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_currentFolderName ?? '${widget.childName}\'s Vault',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        if (_currentFolderId == null)
          Text('Offline Document Storage',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
      ]),
      leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () { if (_currentFolderId != null) { _goBack(); } else { Navigator.pop(context); } }),
      actions: [
        IconButton(icon: const Icon(Icons.search, color: Colors.white), tooltip: 'Search',
            onPressed: () => setState(() => _isSearching = true)),
        IconButton(icon: Icon(_gridView ? Icons.view_list : Icons.grid_view, color: Colors.white),
            tooltip: _gridView ? 'List view' : 'Grid view',
            onPressed: () => setState(() => _gridView = !_gridView)),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white), color: _kDialogBg,
          onSelected: (value) {
            switch (value) {
              case 'trash':
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => VaultTrashScreen(childHash: widget.childHash)),
                ).then((_) { _loadContent(); _loadStats(); });
                break;
              case 'storage': _showStorageDialog(); break;
              case 'sort_name': setState(() => _sortBy = 'name'); _sortContent(); break;
              case 'sort_date': setState(() => _sortBy = 'date'); _sortContent(); break;
              case 'sort_size': setState(() => _sortBy = 'size'); _sortContent(); break;
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'trash', child: Row(children: [
              Icon(Icons.delete_outline, color: Colors.white70, size: 20), SizedBox(width: 10),
              Text('Trash', style: TextStyle(color: Colors.white))])),
            const PopupMenuItem(value: 'storage', child: Row(children: [
              Icon(Icons.storage, color: Colors.white70, size: 20), SizedBox(width: 10),
              Text('Storage Info', style: TextStyle(color: Colors.white))])),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'sort_name', child: Row(children: [
              Icon(Icons.sort_by_alpha, color: _sortBy == 'name' ? _kAccentLight : Colors.white70, size: 20),
              const SizedBox(width: 10),
              Text('Sort by Name', style: TextStyle(color: _sortBy == 'name' ? _kAccentLight : Colors.white))])),
            PopupMenuItem(value: 'sort_date', child: Row(children: [
              Icon(Icons.calendar_today, color: _sortBy == 'date' ? _kAccentLight : Colors.white70, size: 20),
              const SizedBox(width: 10),
              Text('Sort by Date', style: TextStyle(color: _sortBy == 'date' ? _kAccentLight : Colors.white))])),
            PopupMenuItem(value: 'sort_size', child: Row(children: [
              Icon(Icons.data_usage, color: _sortBy == 'size' ? _kAccentLight : Colors.white70, size: 20),
              const SizedBox(width: 10),
              Text('Sort by Size', style: TextStyle(color: _sortBy == 'size' ? _kAccentLight : Colors.white))])),
          ],
        ),
      ],
    );
  }

  void _showStorageDialog() {
    final s = _stats;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Storage Info', style: TextStyle(color: Colors.white)),
        content: s == null
            ? const Text('Loading...', style: TextStyle(color: Colors.white70))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    const Icon(Icons.storage, color: _kAccentLight, size: 36),
                    const SizedBox(height: 8),
                    Text(s['formatted_size'] ?? '0 B',
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    Text('used on device', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
                  ]),
                ),
                const SizedBox(height: 16),
                _detailRow('Files', '${s['file_count'] ?? 0}'),
                _detailRow('Folders', '${s['folder_count'] ?? 0}'),
                _detailRow('In Trash', '${s['trash_count'] ?? 0} (${s['formatted_trash_size'] ?? '0 B'})'),
              ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  // ─── Breadcrumbs ─────────────────────────────────────────────
  Widget _buildBreadcrumbs() {
    if (_breadcrumbs.isEmpty && _currentFolderId == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          GestureDetector(
            onTap: () => _navigateToBreadcrumb(null),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.home, size: 14, color: _kAccentLight),
                const SizedBox(width: 4),
                Text('Root', style: TextStyle(color: _kAccentLight, fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
          for (int i = 0; i < _breadcrumbs.length; i++) ...[
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.chevron_right, size: 16, color: Colors.white.withOpacity(0.3))),
            GestureDetector(
              onTap: i < _breadcrumbs.length - 1 ? () => _navigateToBreadcrumb(_breadcrumbs[i]['id'] as int?) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: i < _breadcrumbs.length - 1 ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6)),
                child: Text(_breadcrumbs[i]['name'] as String? ?? '',
                  style: TextStyle(
                    color: i < _breadcrumbs.length - 1 ? _kAccentLight : Colors.white,
                    fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildStatsBar() {
    if (_stats == null || _currentFolderId != null) return const SizedBox.shrink();
    final fileCount = _stats!['file_count'] ?? 0;
    final folderCount = _stats!['folder_count'] ?? 0;
    final size = _stats!['formatted_size'] ?? '0 B';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _kAccent.withOpacity(0.12), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kAccent.withOpacity(0.2)),
      ),
      child: Row(children: [
        const Icon(Icons.folder_copy_outlined, size: 16, color: _kAccentLight),
        const SizedBox(width: 6),
        Text('$folderCount folders', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
        const SizedBox(width: 12),
        const Icon(Icons.description_outlined, size: 16, color: _kAccentLight),
        const SizedBox(width: 6),
        Text('$fileCount files', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
        const Spacer(),
        Icon(Icons.storage, size: 14, color: Colors.white.withOpacity(0.4)),
        const SizedBox(width: 4),
        Text(size, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
      ]),
    );
  }

  // ─── Main content ────────────────────────────────────────────
  Widget _buildContent() {
    final hasContent = _folders.isNotEmpty || _documents.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        _buildStatsBar(),
        _buildBreadcrumbs(),
        if (!hasContent)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                child: Icon(_currentFolderId != null ? Icons.folder_open : Icons.cloud_off,
                    size: 48, color: Colors.white.withOpacity(0.3)),
              ),
              const SizedBox(height: 16),
              Text(_currentFolderId != null ? 'This folder is empty' : 'No documents yet',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              Text(_currentFolderId != null ? 'Tap + to add files to this folder'
                  : 'All documents are stored offline on your device',
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13)),
            ])),
          )
        else ...[
          if (_folders.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 8),
              child: Row(children: [
                Text('Folders', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13,
                    fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                const Spacer(),
                Text('${_folders.length}', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
              ]),
            ),
            if (_gridView) _buildFolderGrid() else ..._folders.map(_buildFolderTile),
            const SizedBox(height: 8),
          ],
          if (_documents.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Row(children: [
                Text('Documents', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13,
                    fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                const Spacer(),
                Text('${_documents.length}', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
              ]),
            ),
            if (_gridView) _buildDocumentGrid() else ..._documents.map(_buildDocumentTile),
          ],
        ],
      ],
    );
  }

  Widget _buildFolderGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(spacing: 8, runSpacing: 8,
        children: _folders.map((folder) {
          final name = folder['name'] ?? 'Untitled';
          final count = folder['document_count'] ?? 0;
          final type = folder['folder_type'] as String? ?? 'custom';
          final color = _parseFolderColor(folder['color'] as String?);
          return GestureDetector(
            onTap: () => _openFolder(folder),
            child: Container(
              width: (MediaQuery.of(context).size.width - 40) / 2,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _kCardDark, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withOpacity(0.2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(_iconForFolderType(type), color: color, size: 28),
                const SizedBox(height: 10),
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('$count file${count == 1 ? '' : 's'}',
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
              ]),
            ),
          );
        }).toList()),
    );
  }

  Widget _buildDocumentGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(spacing: 8, runSpacing: 8,
        children: _documents.map((doc) {
          final name = doc['display_name'] ?? doc['original_filename'] ?? 'Unknown';
          final category = doc['file_category'] as String?;
          final size = doc['formatted_size'] ?? '';
          final id = doc['id'] as int?;
          return GestureDetector(
            onTap: id != null ? () => _openDocument(id, name) : null,
            onLongPress: id != null ? () => _showDocumentDetails(id) : null,
            child: Container(
              width: (MediaQuery.of(context).size.width - 40) / 2,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _kCardDark, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _colorForCategory(category).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8)),
                  child: Icon(_iconForCategory(category), color: _colorForCategory(category), size: 24),
                ),
                const SizedBox(height: 10),
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(size, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
              ]),
            ),
          );
        }).toList()),
    );
  }

  Widget _buildSearchResults() {
    final hasDocs = _searchDocResults.isNotEmpty;
    final hasFolders = _searchFolderResults.isNotEmpty;
    if (!hasDocs && !hasFolders) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(_searchController.text.isEmpty ? Icons.search : Icons.search_off,
            size: 48, color: Colors.white.withOpacity(0.2)),
        const SizedBox(height: 12),
        Text(_searchController.text.isEmpty ? 'Type to search' : 'No results found',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16)),
      ]));
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      if (hasFolders) ...[
        Padding(padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
          child: Text('Folders', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, fontWeight: FontWeight.w600))),
        ..._searchFolderResults.map(_buildFolderTile),
        const SizedBox(height: 8),
      ],
      if (hasDocs) ...[
        Padding(padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
          child: Text('Documents', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, fontWeight: FontWeight.w600))),
        ..._searchDocResults.map(_buildDocumentTile),
      ],
    ]);
  }

  // ─── Folder tile ─────────────────────────────────────────────
  Widget _buildFolderTile(Map<String, dynamic> folder) {
    final name = folder['name'] ?? 'Untitled';
    final count = folder['document_count'] ?? 0;
    final size = folder['formatted_size'] ?? '';
    final id = folder['id'] as int?;
    final type = folder['folder_type'] as String? ?? 'custom';
    final isStarred = folder['is_starred'] == 1;
    final color = _parseFolderColor(folder['color'] as String?);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: _kCardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
            child: Icon(_iconForFolderType(type), color: color, size: 24),
          ),
          title: Row(children: [
            Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
            if (isStarred) const Icon(Icons.star, color: Colors.amber, size: 16),
          ]),
          subtitle: Text('$count document${count == 1 ? '' : 's'}${size.isNotEmpty ? ' · $size' : ''}',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
          trailing: id != null
              ? PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20), color: _kDialogBg,
                  onSelected: (value) {
                    switch (value) {
                      case 'rename': _showRenameFolderDialog(id, name); break;
                      case 'delete': _deleteFolder(id, name); break;
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
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
    final name = (doc['display_name'] ?? doc['original_filename'] ?? 'Unknown') as String;
    final category = doc['file_category'] as String?;
    final size = (doc['formatted_size'] ?? '') as String;
    final id = doc['id'] as int?;
    final isStarred = doc['is_starred'] == 1;
    final createdAt = doc['created_at'] as String?;

    String dateStr = '';
    if (createdAt != null) {
      try { dateStr = DateFormat('MMM d, yyyy').format(DateTime.parse(createdAt)); } catch (_) {}
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
            decoration: BoxDecoration(color: _colorForCategory(category).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(_iconForCategory(category), color: _colorForCategory(category), size: 24),
          ),
          title: Row(children: [
            Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (isStarred) const Padding(padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.star, color: Colors.amber, size: 16)),
          ]),
          subtitle: Text([if (size.isNotEmpty) size, if (dateStr.isNotEmpty) dateStr].join(' · '),
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
          trailing: id != null ? PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20), color: _kDialogBg,
            onSelected: (value) {
              switch (value) {
                case 'open': _openDocument(id, name); break;
                case 'details': _showDocumentDetails(id); break;
                case 'star': _toggleStarDocument(id, isStarred); break;
                case 'rename': _renameDocument(id, name); break;
                case 'move': _moveDocument(id, name); break;
                case 'delete': _deleteDocument(id, name); break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'open', child: Row(children: [
                Icon(Icons.open_in_new, color: Colors.white70, size: 18), SizedBox(width: 8),
                Text('Open', style: TextStyle(color: Colors.white))])),
              const PopupMenuItem(value: 'details', child: Row(children: [
                Icon(Icons.info_outline, color: Colors.white70, size: 18), SizedBox(width: 8),
                Text('Details', style: TextStyle(color: Colors.white))])),
              PopupMenuItem(value: 'star', child: Row(children: [
                Icon(isStarred ? Icons.star_border : Icons.star, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Text(isStarred ? 'Unstar' : 'Star', style: const TextStyle(color: Colors.white))])),
              const PopupMenuItem(value: 'rename', child: Row(children: [
                Icon(Icons.edit, color: Colors.white70, size: 18), SizedBox(width: 8),
                Text('Rename', style: TextStyle(color: Colors.white))])),
              const PopupMenuItem(value: 'move', child: Row(children: [
                Icon(Icons.drive_file_move_outlined, color: Colors.white70, size: 18), SizedBox(width: 8),
                Text('Move to Folder', style: TextStyle(color: Colors.white))])),
              const PopupMenuItem(value: 'delete', child: Row(children: [
                Icon(Icons.delete_outline, color: Colors.redAccent, size: 18), SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.redAccent))])),
            ],
          ) : null,
          onTap: id != null ? () => _openDocument(id, name) : null,
        ),
      ),
    );
  }
}
