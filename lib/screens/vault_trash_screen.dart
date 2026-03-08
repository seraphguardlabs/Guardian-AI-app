import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/preferences_manager.dart';

const _kBgDark = Color(0xFF0D0D1A);
const _kCardDark = Color(0xFF1A1A2E);
const _kDialogBg = Color(0xFF1E1E2C);
const _kAccent = Color(0xFF283C9A);
const _kAccentLight = Color(0xFF5B8DEF);

class VaultTrashScreen extends StatefulWidget {
  const VaultTrashScreen({super.key});

  @override
  State<VaultTrashScreen> createState() => _VaultTrashScreenState();
}

class _VaultTrashScreenState extends State<VaultTrashScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _trashedDocs = [];

  ApiService get _api => Provider.of<ApiService>(context, listen: false);
  String get _email =>
      Provider.of<PreferencesManager>(context, listen: false).getParentEmail() ?? '';
  String get _password =>
      Provider.of<PreferencesManager>(context, listen: false).getParentPassword() ?? '';

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    setState(() => _loading = true);
    final result = await _api.listVaultTrash(email: _email, password: _password);
    if (!mounted) return;
    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>? ?? {};
      setState(() {
        _trashedDocs = List<Map<String, dynamic>>.from(data['documents'] ?? []);
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load trash: ${result['error']}')),
      );
    }
  }

  Future<void> _restoreDocument(int documentId, String name) async {
    final result = await _api.restoreVaultDocument(
      email: _email,
      password: _password,
      documentId: documentId,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$name" restored')),
      );
      _loadTrash();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: ${result['error']}')),
      );
    }
  }

  Future<void> _permanentlyDelete(int documentId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        title: const Text('Permanently Delete', style: TextStyle(color: Colors.white)),
        content: Text(
          'Permanently delete "$name"?\nThis cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Forever', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await _api.deleteVaultDocument(
      email: _email,
      password: _password,
      documentId: documentId,
      permanent: true,
    );

    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$name" permanently deleted')),
      );
      _loadTrash();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${result['error']}')),
      );
    }
  }

  Future<void> _emptyTrash() async {
    if (_trashedDocs.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        title: const Text('Empty Trash', style: TextStyle(color: Colors.white)),
        content: Text(
          'Permanently delete all ${_trashedDocs.length} item(s)?\nThis cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Empty Trash', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await _api.emptyVaultTrash(email: _email, password: _password);
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trash emptied')),
      );
      _loadTrash();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${result['error']}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgDark,
      appBar: AppBar(
        backgroundColor: _kBgDark,
        elevation: 0,
        title: const Text('Trash', style: TextStyle(color: Colors.white, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_trashedDocs.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 20),
              label: const Text('Empty', style: TextStyle(color: Colors.redAccent)),
              onPressed: _emptyTrash,
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadTrash,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trashedDocs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline, size: 64, color: Colors.white.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      Text('Trash is empty',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTrash,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _trashedDocs.length,
                    itemBuilder: (ctx, i) => _buildTrashTile(_trashedDocs[i]),
                  ),
                ),
    );
  }

  Widget _buildTrashTile(Map<String, dynamic> doc) {
    final name = doc['name'] ?? doc['original_filename'] ?? 'Unknown';
    final category = doc['file_category'] as String?;
    final size = doc['formatted_size'] ?? '';
    final id = doc['id'] as int?;
    final deletedAt = doc['deleted_at'] as String?;

    String dateStr = '';
    if (deletedAt != null) {
      try {
        dateStr = 'Deleted ${DateFormat('MMM d, yyyy').format(DateTime.parse(deletedAt))}';
      } catch (_) {}
    }

    return Card(
      color: _kCardDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_iconForCategory(category), color: Colors.white38, size: 24),
        ),
        title: Text(name,
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [if (size.isNotEmpty) size, if (dateStr.isNotEmpty) dateStr].join(' · '),
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
        ),
        trailing: id != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.restore, color: Colors.greenAccent, size: 22),
                    tooltip: 'Restore',
                    onPressed: () => _restoreDocument(id, name),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 22),
                    tooltip: 'Delete forever',
                    onPressed: () => _permanentlyDelete(id, name),
                  ),
                ],
              )
            : null,
      ),
    );
  }

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
}
