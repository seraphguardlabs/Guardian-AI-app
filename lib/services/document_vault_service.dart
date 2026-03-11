import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

// ─── Preset folder types with icons and colors ─────────────────
class VaultFolderType {
  final String key;
  final String label;
  final String iconName;
  final String color;

  const VaultFolderType({
    required this.key,
    required this.label,
    required this.iconName,
    required this.color,
  });

  static const List<VaultFolderType> presets = [
    VaultFolderType(key: 'medical', label: 'Medical Records', iconName: 'medical_services', color: '#E53935'),
    VaultFolderType(key: 'school', label: 'School Documents', iconName: 'school', color: '#1E88E5'),
    VaultFolderType(key: 'legal', label: 'Legal Documents', iconName: 'gavel', color: '#6D4C41'),
    VaultFolderType(key: 'photos', label: 'Photos & Memories', iconName: 'photo_library', color: '#43A047'),
    VaultFolderType(key: 'certificates', label: 'Certificates', iconName: 'workspace_premium', color: '#FDD835'),
    VaultFolderType(key: 'financial', label: 'Financial', iconName: 'account_balance', color: '#00897B'),
    VaultFolderType(key: 'ids', label: 'IDs & Passports', iconName: 'badge', color: '#8E24AA'),
    VaultFolderType(key: 'insurance', label: 'Insurance', iconName: 'health_and_safety', color: '#F4511E'),
    VaultFolderType(key: 'emergency', label: 'Emergency Info', iconName: 'emergency', color: '#D32F2F'),
    VaultFolderType(key: 'custom', label: 'Custom', iconName: 'folder', color: '#5B8DEF'),
  ];

  static VaultFolderType fromKey(String key) {
    return presets.firstWhere((t) => t.key == key, orElse: () => presets.last);
  }
}

// ─── File category detection ───────────────────────────────────
String detectFileCategory(String filename) {
  final ext = p.extension(filename).toLowerCase().replaceAll('.', '');
  switch (ext) {
    case 'pdf':
      return 'pdf';
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'webp':
    case 'bmp':
    case 'svg':
      return 'image';
    case 'doc':
    case 'docx':
    case 'txt':
    case 'rtf':
    case 'odt':
      return 'document';
    case 'xls':
    case 'xlsx':
    case 'csv':
    case 'ods':
      return 'spreadsheet';
    case 'ppt':
    case 'pptx':
    case 'odp':
      return 'presentation';
    case 'mp3':
    case 'wav':
    case 'ogg':
    case 'aac':
    case 'flac':
    case 'm4a':
      return 'audio';
    case 'mp4':
    case 'mov':
    case 'avi':
    case 'mkv':
    case 'webm':
      return 'video';
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return 'archive';
    default:
      return 'other';
  }
}

String detectMimeType(String filename) {
  final ext = p.extension(filename).toLowerCase().replaceAll('.', '');
  const mimeMap = {
    'pdf': 'application/pdf',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'bmp': 'image/bmp',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'rtf': 'application/rtf',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'aac': 'audio/aac',
    'flac': 'audio/flac',
    'm4a': 'audio/mp4',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'avi': 'video/x-msvideo',
    'mkv': 'video/x-matroska',
    'webm': 'video/webm',
    'zip': 'application/zip',
    'rar': 'application/x-rar-compressed',
    '7z': 'application/x-7z-compressed',
  };
  return mimeMap[ext] ?? 'application/octet-stream';
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

// ─── Document Vault Service (fully offline) ────────────────────
class DocumentVaultService {
  static final DocumentVaultService _instance = DocumentVaultService._();
  factory DocumentVaultService() => _instance;
  DocumentVaultService._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<String> get _vaultPath async {
    final dir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(dir.path, 'document_vault'));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    return vaultDir.path;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'document_vault.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            parent_id INTEGER,
            child_hash TEXT NOT NULL,
            color TEXT DEFAULT '#5B8DEF',
            icon_name TEXT DEFAULT 'folder',
            folder_type TEXT DEFAULT 'custom',
            is_starred INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (parent_id) REFERENCES folders(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE documents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            display_name TEXT NOT NULL,
            original_filename TEXT NOT NULL,
            file_path TEXT NOT NULL,
            file_size INTEGER NOT NULL DEFAULT 0,
            mime_type TEXT DEFAULT 'application/octet-stream',
            file_category TEXT DEFAULT 'other',
            folder_id INTEGER,
            child_hash TEXT NOT NULL,
            description TEXT DEFAULT '',
            is_starred INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0,
            tags TEXT DEFAULT '[]',
            access_count INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT,
            FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE SET NULL
          )
        ''');

        await db.execute('CREATE INDEX idx_docs_child ON documents(child_hash)');
        await db.execute('CREATE INDEX idx_docs_folder ON documents(folder_id)');
        await db.execute('CREATE INDEX idx_docs_deleted ON documents(is_deleted)');
        await db.execute('CREATE INDEX idx_folders_child ON folders(child_hash)');
        await db.execute('CREATE INDEX idx_folders_parent ON folders(parent_id)');
      },
    );
  }

  // ─── Folder operations ─────────────────────────────────────
  Future<List<Map<String, dynamic>>> listFolders({
    required String childHash,
    int? parentId,
  }) async {
    final db = await database;
    final where = parentId == null
        ? 'child_hash = ? AND parent_id IS NULL'
        : 'child_hash = ? AND parent_id = ?';
    final args = parentId == null ? [childHash] : [childHash, parentId];

    final folders = await db.query('folders', where: where, whereArgs: args, orderBy: 'name ASC');

    final result = <Map<String, dynamic>>[];
    for (final f in folders) {
      final docCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM documents WHERE folder_id = ? AND is_deleted = 0',
        [f['id']],
      )) ?? 0;
      final totalSize = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COALESCE(SUM(file_size), 0) FROM documents WHERE folder_id = ? AND is_deleted = 0',
        [f['id']],
      )) ?? 0;

      result.add({
        ...f,
        'document_count': docCount,
        'total_size': totalSize,
        'formatted_size': formatFileSize(totalSize),
      });
    }
    return result;
  }

  Future<Map<String, dynamic>> getFolderDetails({required int folderId}) async {
    final db = await database;
    final folders = await db.query('folders', where: 'id = ?', whereArgs: [folderId]);
    if (folders.isEmpty) return {};

    final folder = folders.first;
    final childHash = folder['child_hash'] as String;

    final subfolders = await listFolders(childHash: childHash, parentId: folderId);
    final documents = await listDocuments(childHash: childHash, folderId: folderId);
    final breadcrumbs = await _buildBreadcrumbs(folderId);

    return {
      'folder': folder,
      'subfolders': subfolders,
      'documents': documents,
      'breadcrumb': breadcrumbs,
    };
  }

  Future<List<Map<String, dynamic>>> _buildBreadcrumbs(int folderId) async {
    final db = await database;
    final crumbs = <Map<String, dynamic>>[];
    int? currentId = folderId;

    while (currentId != null) {
      final rows = await db.query('folders', where: 'id = ?', whereArgs: [currentId]);
      if (rows.isEmpty) break;
      crumbs.insert(0, {'id': rows.first['id'], 'name': rows.first['name']});
      currentId = rows.first['parent_id'] as int?;
    }
    return crumbs;
  }

  Future<int> createFolder({
    required String name,
    required String childHash,
    int? parentId,
    String folderType = 'custom',
    String? color,
    String? iconName,
  }) async {
    final db = await database;
    final type = VaultFolderType.fromKey(folderType);
    final now = DateTime.now().toIso8601String();

    return await db.insert('folders', {
      'name': name,
      'parent_id': parentId,
      'child_hash': childHash,
      'color': color ?? type.color,
      'icon_name': iconName ?? type.iconName,
      'folder_type': folderType,
      'is_starred': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateFolder({
    required int folderId,
    String? name,
    String? color,
    String? iconName,
    bool? isStarred,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (name != null) updates['name'] = name;
    if (color != null) updates['color'] = color;
    if (iconName != null) updates['icon_name'] = iconName;
    if (isStarred != null) updates['is_starred'] = isStarred ? 1 : 0;

    await db.update('folders', updates, where: 'id = ?', whereArgs: [folderId]);
  }

  Future<void> deleteFolder({required int folderId}) async {
    final db = await database;

    // Get all documents in this folder (and subfolders recursively)
    final docsToDelete = await _getDocumentsRecursive(folderId);
    for (final doc in docsToDelete) {
      final filePath = doc['file_path'] as String?;
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) await file.delete();
      }
    }

    // Delete subfolders recursively
    final subfolders = await db.query('folders', where: 'parent_id = ?', whereArgs: [folderId]);
    for (final sub in subfolders) {
      await deleteFolder(folderId: sub['id'] as int);
    }

    // Delete documents in this folder
    await db.delete('documents', where: 'folder_id = ?', whereArgs: [folderId]);
    // Delete the folder itself
    await db.delete('folders', where: 'id = ?', whereArgs: [folderId]);
  }

  Future<List<Map<String, dynamic>>> _getDocumentsRecursive(int folderId) async {
    final db = await database;
    final docs = await db.query('documents', where: 'folder_id = ?', whereArgs: [folderId]);
    final subfolders = await db.query('folders', where: 'parent_id = ?', whereArgs: [folderId]);

    final allDocs = List<Map<String, dynamic>>.from(docs);
    for (final sub in subfolders) {
      allDocs.addAll(await _getDocumentsRecursive(sub['id'] as int));
    }
    return allDocs;
  }

  /// Create all preset folders for a child if they don't exist yet.
  Future<void> ensurePresetFolders({required String childHash}) async {
    final db = await database;
    final existing = await db.query(
      'folders',
      where: 'child_hash = ? AND parent_id IS NULL',
      whereArgs: [childHash],
    );

    final existingTypes = existing.map((f) => f['folder_type'] as String?).toSet();

    for (final preset in VaultFolderType.presets) {
      if (preset.key == 'custom') continue; // Don't auto-create "Custom"
      if (existingTypes.contains(preset.key)) continue;

      await createFolder(
        name: preset.label,
        childHash: childHash,
        folderType: preset.key,
        color: preset.color,
        iconName: preset.iconName,
      );
    }
  }

  // ─── Document operations ───────────────────────────────────
  Future<List<Map<String, dynamic>>> listDocuments({
    required String childHash,
    int? folderId,
  }) async {
    final db = await database;
    String where;
    List<dynamic> args;

    if (folderId != null) {
      where = 'child_hash = ? AND folder_id = ? AND is_deleted = 0';
      args = [childHash, folderId];
    } else {
      where = 'child_hash = ? AND folder_id IS NULL AND is_deleted = 0';
      args = [childHash];
    }

    final docs = await db.query('documents', where: where, whereArgs: args, orderBy: 'created_at DESC');
    return docs.map((d) => {
      ...d,
      'formatted_size': formatFileSize((d['file_size'] as int?) ?? 0),
      'tags': jsonDecode((d['tags'] as String?) ?? '[]'),
    }).toList();
  }

  Future<Map<String, dynamic>?> getDocumentDetails({required int documentId}) async {
    final db = await database;
    final docs = await db.query('documents', where: 'id = ?', whereArgs: [documentId]);
    if (docs.isEmpty) return null;
    final d = docs.first;
    return {
      ...d,
      'formatted_size': formatFileSize((d['file_size'] as int?) ?? 0),
      'tags': jsonDecode((d['tags'] as String?) ?? '[]'),
    };
  }

  Future<int> addDocument({
    required String sourcePath,
    required String displayName,
    required String originalFilename,
    required String childHash,
    int? folderId,
    String? description,
    List<String>? tags,
  }) async {
    final db = await database;
    final vaultRoot = await _vaultPath;
    final sourceFile = File(sourcePath);

    if (!await sourceFile.exists()) {
      throw Exception('Source file does not exist');
    }

    final fileSize = await sourceFile.length();
    final category = detectFileCategory(originalFilename);
    final mime = detectMimeType(originalFilename);
    final ext = p.extension(originalFilename);
    final now = DateTime.now();
    final sanitizedName = displayName.replaceAll(RegExp(r'[^\w.\-\s]'), '_');
    final storageName = '${now.millisecondsSinceEpoch}_$sanitizedName';
    final destPath = p.join(vaultRoot, childHash, storageName);

    // Create child directory
    final destDir = Directory(p.join(vaultRoot, childHash));
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    // Copy file to vault storage
    await sourceFile.copy(destPath);

    final id = await db.insert('documents', {
      'display_name': displayName,
      'original_filename': originalFilename,
      'file_path': destPath,
      'file_size': fileSize,
      'mime_type': mime,
      'file_category': category,
      'folder_id': folderId,
      'child_hash': childHash,
      'description': description ?? '',
      'is_starred': 0,
      'is_deleted': 0,
      'tags': jsonEncode(tags ?? []),
      'access_count': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    return id;
  }

  Future<void> updateDocument({
    required int documentId,
    String? displayName,
    String? description,
    List<String>? tags,
    bool? isStarred,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (displayName != null) updates['display_name'] = displayName;
    if (description != null) updates['description'] = description;
    if (tags != null) updates['tags'] = jsonEncode(tags);
    if (isStarred != null) updates['is_starred'] = isStarred ? 1 : 0;

    await db.update('documents', updates, where: 'id = ?', whereArgs: [documentId]);
  }

  Future<void> moveDocument({required int documentId, int? folderId}) async {
    final db = await database;
    await db.update(
      'documents',
      {'folder_id': folderId, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }

  /// Soft delete — moves to trash
  Future<void> softDeleteDocument({required int documentId}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'documents',
      {'is_deleted': 1, 'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }

  /// Permanent delete — removes file and DB row
  Future<void> permanentDeleteDocument({required int documentId}) async {
    final db = await database;
    final docs = await db.query('documents', where: 'id = ?', whereArgs: [documentId]);
    if (docs.isNotEmpty) {
      final filePath = docs.first['file_path'] as String?;
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) await file.delete();
      }
    }
    await db.delete('documents', where: 'id = ?', whereArgs: [documentId]);
  }

  /// Restore from trash
  Future<void> restoreDocument({required int documentId}) async {
    final db = await database;
    await db.update(
      'documents',
      {'is_deleted': 0, 'deleted_at': null, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }

  /// Increment access count
  Future<void> trackAccess({required int documentId}) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE documents SET access_count = access_count + 1, updated_at = ? WHERE id = ?',
      [DateTime.now().toIso8601String(), documentId],
    );
  }

  // ─── Trash operations ──────────────────────────────────────
  Future<List<Map<String, dynamic>>> listTrash({required String childHash}) async {
    final db = await database;
    final docs = await db.query(
      'documents',
      where: 'child_hash = ? AND is_deleted = 1',
      whereArgs: [childHash],
      orderBy: 'deleted_at DESC',
    );
    return docs.map((d) => {
      ...d,
      'formatted_size': formatFileSize((d['file_size'] as int?) ?? 0),
    }).toList();
  }

  Future<void> emptyTrash({required String childHash}) async {
    final db = await database;
    final docs = await db.query(
      'documents',
      where: 'child_hash = ? AND is_deleted = 1',
      whereArgs: [childHash],
    );
    for (final doc in docs) {
      final filePath = doc['file_path'] as String?;
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) await file.delete();
      }
    }
    await db.delete(
      'documents',
      where: 'child_hash = ? AND is_deleted = 1',
      whereArgs: [childHash],
    );
  }

  // ─── Search ────────────────────────────────────────────────
  Future<Map<String, List<Map<String, dynamic>>>> search({
    required String childHash,
    required String query,
  }) async {
    final db = await database;
    final q = '%$query%';

    final docs = await db.query(
      'documents',
      where: 'child_hash = ? AND is_deleted = 0 AND (display_name LIKE ? OR original_filename LIKE ? OR description LIKE ? OR tags LIKE ?)',
      whereArgs: [childHash, q, q, q, q],
      orderBy: 'created_at DESC',
    );

    final folders = await db.query(
      'folders',
      where: 'child_hash = ? AND name LIKE ?',
      whereArgs: [childHash, q],
      orderBy: 'name ASC',
    );

    return {
      'documents': docs.map((d) => {
        ...d,
        'formatted_size': formatFileSize((d['file_size'] as int?) ?? 0),
      }).toList(),
      'folders': folders.toList(),
    };
  }

  // ─── Storage stats ─────────────────────────────────────────
  Future<Map<String, dynamic>> getStorageStats({required String childHash}) async {
    final db = await database;

    final totalSize = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COALESCE(SUM(file_size), 0) FROM documents WHERE child_hash = ? AND is_deleted = 0',
      [childHash],
    )) ?? 0;

    final fileCount = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM documents WHERE child_hash = ? AND is_deleted = 0',
      [childHash],
    )) ?? 0;

    final trashSize = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COALESCE(SUM(file_size), 0) FROM documents WHERE child_hash = ? AND is_deleted = 1',
      [childHash],
    )) ?? 0;

    final trashCount = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM documents WHERE child_hash = ? AND is_deleted = 1',
      [childHash],
    )) ?? 0;

    final folderCount = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM folders WHERE child_hash = ?',
      [childHash],
    )) ?? 0;

    return {
      'total_size': totalSize,
      'formatted_size': formatFileSize(totalSize),
      'file_count': fileCount,
      'trash_size': trashSize,
      'formatted_trash_size': formatFileSize(trashSize),
      'trash_count': trashCount,
      'folder_count': folderCount,
    };
  }

  /// Get the local file path for a document (for opening/sharing)
  Future<String?> getDocumentFilePath({required int documentId}) async {
    final db = await database;
    final docs = await db.query('documents', columns: ['file_path'], where: 'id = ?', whereArgs: [documentId]);
    if (docs.isEmpty) return null;
    final path = docs.first['file_path'] as String?;
    if (path != null && await File(path).exists()) return path;
    return null;
  }
}
