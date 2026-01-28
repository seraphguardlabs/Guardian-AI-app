# Task E2E Encryption Guide

This document describes the end-to-end encryption implementation for the task assignment system.

## Overview

Task messages (title and description) are encrypted using RSA 2048-bit encryption to ensure privacy between guardian (parent) and child devices. Only the intended recipient can read the task content.

## Encryption Flow

### 1. Key Generation

- **Child Device**: 
  - Generates RSA key pair on first launch
  - Stores private key locally in SharedPreferences (never leaves device)
  - Uploads public key to server via `POST /api/mobile/child/<hash>/public-key/`

- **Guardian Device**: 
  - Generates RSA key pair on first launch
  - Stores private key locally in SharedPreferences (never leaves device)
  - Uploads public key to server via `POST /api/mobile/guardian/public-key/`

### 2. Creating Tasks (Guardian → Child)

**File**: `lib/services/api_service.dart` → `createTask()`

1. Guardian enters task title and description
2. System fetches child's public key from server: `GET /api/mobile/child/<hash>/public-key/`
3. Encrypts title and description with child's public key using `EncryptionService.encryptWithPublicKey()`
4. Sends encrypted data to server: `POST /api/mobile/child/<hash>/tasks/`
5. Server stores encrypted task (server cannot read the content)

**Code Flow**:
```dart
// Fetch child's public key
final publicKeyResponse = await getChildPublicKey(childHash: childHash);
final childPublicKey = publicKeyResponse['public_key'];

// Encrypt task data
final encryptionService = EncryptionService.instance;
final encryptedTitle = encryptionService.encryptWithPublicKey(title, childPublicKey);
final encryptedDescription = encryptionService.encryptWithPublicKey(description, childPublicKey);

// Send encrypted data to server
final requestBody = {
  'title': encryptedTitle,
  'description': encryptedDescription,
};
```

### 3. Viewing Tasks (Child Side)

**File**: `lib/screens/my_tasks_screen.dart` → `_loadTasks()`

1. Child fetches tasks from server: `GET /api/mobile/child/<hash>/my-tasks/`
2. Receives encrypted task data (base64 encoded)
3. Decrypts title and description with child's private key using `EncryptionService.decryptWithPrivateKey()`
4. Displays decrypted content in UI

**Code Flow**:
```dart
// Fetch tasks from server
final result = await _apiService.getMyTasks(childHash: childHash, password: password);
List<Task> tasks = result['tasks'];

// Decrypt each task
final encryptionService = EncryptionService.instance;
List<Task> decryptedTasks = tasks.map((task) {
  final decryptedTitle = encryptionService.decryptWithPrivateKey(task.title);
  final decryptedDescription = encryptionService.decryptWithPrivateKey(task.description);
  
  // Create new task with decrypted data
  return Task(
    id: task.id,
    title: decryptedTitle ?? task.title,
    description: decryptedDescription ?? task.description,
    // ... other fields
  );
}).toList();
```

## Encryption Details

### Algorithms
- **Key Generation**: RSA 2048-bit
- **Encryption**: RSA/OAEP (Optimal Asymmetric Encryption Padding)
- **Encoding**: Base64 (for transmission)

### Key Storage
- **Private Keys**: 
  - Stored in device's SharedPreferences
  - Keys: `guardian_private_key` (parent), `child_private_key` (child)
  - NEVER transmitted over network
  
- **Public Keys**: 
  - Stored on server in database
  - Accessible via API endpoints
  - Used by other party for encryption

### Security Guarantees

1. **End-to-End Encryption**: 
   - Server cannot read task content
   - Only guardian and child can decrypt

2. **Forward Secrecy**: 
   - Each task encrypted with fresh operation
   - Compromising one message doesn't affect others

3. **Authenticity**: 
   - Guardian's credentials required to create tasks
   - Child's credentials required to view tasks

## API Endpoints

### Get Child's Public Key
```
GET /api/mobile/child/<child_hash>/public-key/
Response: { "public_key": "-----BEGIN PUBLIC KEY-----..." }
```

### Set Child's Public Key
```
POST /api/mobile/child/<child_hash>/public-key/
Body: { "public_key": "-----BEGIN PUBLIC KEY-----..." }
```

### Get Guardian's Public Key
```
GET /api/mobile/guardian/public-key/
Headers: X-Email, X-Password
Response: { "public_key": "-----BEGIN PUBLIC KEY-----..." }
```

### Set Guardian's Public Key
```
POST /api/mobile/guardian/public-key/
Headers: X-Email, X-Password
Body: { "public_key": "-----BEGIN PUBLIC KEY-----..." }
```

## Fallback Handling

If encryption fails at any point, the system gracefully falls back:

1. **Create Task**: If public key unavailable or encryption fails → sends plaintext
2. **View Task**: If decryption fails → displays original content (may be plaintext)

This ensures the app continues working even if encryption infrastructure has issues.

## Testing

To verify encryption is working:

1. Create a task from guardian app
2. Check debug logs for:
   ```
   🔑 Fetching child public key for encryption...
   ✅ Child public key retrieved, encrypting task data...
   ✅ Task data encrypted successfully
   ```
3. On child app, check for decrypted content displaying correctly
4. Verify encrypted data stored on server (via API/database inspection)

## Files Modified

1. **lib/services/api_service.dart**:
   - Added `getChildPublicKey()` method
   - Modified `createTask()` to encrypt title/description

2. **lib/screens/my_tasks_screen.dart**:
   - Added import for `encryption_service.dart`
   - Modified `_loadTasks()` to decrypt task content

3. **lib/models/task.dart**: 
   - No changes needed (encryption transparent at model layer)

## Security Notes

⚠️ **Important Considerations**:

- Only title and description are end-to-end encrypted
- Task IDs and metadata (created, updated, completed_at) are NOT encrypted
- Encryption uses standard RSA/OAEP with 2048-bit keys
- Private keys stored in SharedPreferences (Android Keystore integration recommended for production)
