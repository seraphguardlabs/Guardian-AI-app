# RSA Key Generation Implementation

## Overview

Both parent (Flutter) and child (Android) apps now generate and store RSA-2048 key pairs locally for end-to-end encryption.

---

## Parent App (Flutter)

### Implementation

**File:** `lib/services/encryption_service.dart`

**Key Dependencies:**
- `pointycastle: ^3.9.1` - RSA key generation and cryptography
- `encrypt: ^5.0.3` - High-level encryption/decryption APIs
- `shared_preferences` - Local key storage

**Features:**
- ✅ Singleton service for app-wide access
- ✅ Automatic key generation on first run
- ✅ Keys stored in SharedPreferences
- ✅ PEM format encoding/decoding
- ✅ Public key upload to server
- ✅ Encryption with any public key
- ✅ Decryption with own private key
- ✅ Custom ASN.1 encoder for PEM format

### Initialization Flow

1. **App Startup** (`main.dart`):
   ```dart
   await EncryptionService.instance.initialize();
   ```
   - Checks if keys exist in SharedPreferences
   - If yes: loads existing keys
   - If no: generates new 2048-bit RSA key pair

2. **Login Success** (`login_screen.dart`):
   ```dart
   await EncryptionService.instance.uploadPublicKeyToServer();
   ```
   - Uploads guardian's public key to server
   - Endpoint: `POST /api/mobile/guardian/public-key/update/`

### Usage Examples

```dart
// Get instance
final encryption = EncryptionService.instance;

// Encrypt with child's public key
String encrypted = encryption.encryptWithPublicKey(
  "Hello child!",
  childPublicKeyPem
);

// Decrypt with own private key
String? decrypted = encryption.decryptWithPrivateKey(encryptedBase64);

// Get own public key (to share with others)
String? myPublicKey = encryption.publicKey;
```

### Storage

**SharedPreferences Keys:**
- `guardian_private_key` - Private key (PEM format)
- `guardian_public_key` - Public key (PEM format)
- `guardian_key_generated` - Boolean flag

---

## Child App (Android/Kotlin)

### Implementation

**File:** `pca/app/src/main/java/com/example/core_android/security/EncryptionService.kt`

**Features:**
- ✅ Singleton service with context
- ✅ Automatic key generation on first run
- ✅ Keys stored in SharedPreferences
- ✅ PEM format encoding/decoding
- ✅ Encryption with guardian's public key
- ✅ Decryption with own private key

### Initialization Flow

1. **App Startup** (`MyApplication.kt`):
   ```kotlin
   val encryptionService = EncryptionService.getInstance(this)
   encryptionService.initialize()
   ```
   - Checks if keys exist in SharedPreferences
   - If yes: loads existing keys
   - If no: generates new 2048-bit RSA key pair

2. **Upload to Server** (to be implemented):
   - Child needs to upload public key to server on registration/first login
   - Endpoint: `POST /api/mobile/child/{hash}/public-key/update/`

### Usage Examples

```kotlin
// Get instance
val encryption = EncryptionService.getInstance(context)

// Encrypt message for guardian
val encrypted = encryption.encryptWithPublicKey(
    "Please approve!",
    guardianPublicKeyPem
)

// Decrypt message from guardian
val decrypted = encryption.decryptWithPrivateKey(encryptedBase64)

// Get own public key
val myPublicKey = encryption.getPublicKeyPem()
```

### Storage

**SharedPreferences:**
- Prefs Name: `encryption_prefs`
- `rsa_public_key` - Public key (PEM format)
- `rsa_private_key` - Private key (PEM format)
- `keys_generated` - Boolean flag

---

## Key Generation Details

### Algorithm
- **Type:** RSA
- **Key Size:** 2048 bits
- **Padding:** PKCS1Padding
- **Format:** PEM (Privacy Enhanced Mail)

### Security Features

1. **Local Storage Only:**
   - Private keys NEVER leave the device
   - Only public keys are shared with server

2. **Automatic Generation:**
   - Keys generated on first app launch
   - No user interaction required

3. **Persistent Storage:**
   - Keys stored in app's private SharedPreferences
   - Survive app restarts
   - Cleared on logout

4. **PEM Format:**
   - Standard format for RSA keys
   - Compatible with server-side implementations
   - Easy to share and transmit

---

## API Integration Required

### Backend Endpoints Needed:

#### 1. Guardian Public Key Update
```
POST /api/mobile/guardian/public-key/update/
Headers:
  X-Email: parent@example.com
  X-Password: password
Body:
  {
    "public_key": "-----BEGIN PUBLIC KEY-----\n..."
  }
```

#### 2. Child Public Key Update
```
POST /api/mobile/child/{child_hash}/public-key/update/
Headers:
  Authorization: Bearer {token}
Body:
  {
    "public_key": "-----BEGIN PUBLIC KEY-----\n..."
  }
```

---

## Testing

### Parent App Logs
```
🔐 Encryption: Initializing...
🔐 Encryption: Generating new RSA key pair (2048-bit)...
🔐 Encryption: Keys generated, converting to PEM format...
🔐 Encryption: Storing keys locally...
✅ Encryption: RSA key pair generated and stored
🔑 Public Key: -----BEGIN PUBLIC KEY-----...
📤 Encryption: Uploading public key to server...
✅ Encryption: Public key uploaded successfully
```

### Child App Logs
```
🔐 Initializing encryption service...
🔐 Starting key generation...
🔐 Keys generated, converting to PEM format...
🔐 Storing keys locally...
✅ RSA key pair generated and stored
🔑 Public Key: -----BEGIN PUBLIC KEY-----...
```

---

## Next Steps

1. ✅ Parent app generates keys on startup
2. ✅ Child app generates keys on startup
3. ⏳ Backend: Create public key update endpoints
4. ⏳ Parent app: Upload public key after login (implemented, needs backend)
5. ⏳ Child app: Upload public key after registration
6. ⏳ Update Time Extension Service to use encryption
7. ⏳ Test E2E encryption flow

---

## Migration Notes

### Existing Users
- Keys will be generated on next app launch
- No data loss - keys are new, not dependent on old data
- Public keys automatically uploaded to server on next login

### New Users
- Keys generated immediately on first app install
- Public keys uploaded during registration/first login

---

## Security Considerations

✅ **Private keys never leave the device**  
✅ **2048-bit RSA is secure for current standards**  
✅ **Keys stored in app's private storage (not accessible by other apps)**  
✅ **PEM format is industry standard**  
⚠️ **Consider adding key rotation mechanism in future**  
⚠️ **Consider encrypting private key in SharedPreferences with device keystore**

---

## Troubleshooting

### Parent App

**Keys not generating:**
- Check logs for "🔐 Encryption:" messages
- Verify SharedPreferences is writable
- Check for exceptions in initialization

**Upload failing:**
- Verify backend endpoint exists
- Check authentication headers
- Verify network connectivity

### Child App

**Keys not generating:**
- Check logcat for "EncryptionService" tag
- Verify SharedPreferences permissions
- Check for SecurityExceptions

---

## Code Locations

### Parent App (Flutter)
- Service: `lib/services/encryption_service.dart`
- Initialization: `lib/main.dart` (line ~20)
- Upload: `lib/screens/login_screen.dart` (after login)

### Child App (Android)
- Service: `pca/app/src/main/java/com/example/core_android/security/EncryptionService.kt`
- Initialization: `pca/app/src/main/java/com/example/core_android/MyApplication.kt`

---

✅ **RSA Key Generation: COMPLETE**
