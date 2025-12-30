import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/api.dart' as pc;
import 'package:http/http.dart' as http;

class EncryptionService {
  static const String baseUrl = 'https://seraphguardlabs.com';
  static const String _privateKeyKey = 'guardian_private_key';
  static const String _publicKeyKey = 'guardian_public_key';
  static const String _keyGeneratedKey = 'guardian_key_generated';
  
  static EncryptionService? _instance;
  
  String? _privateKey;
  String? _publicKey;
  bool _isInitialized = false;
  
  EncryptionService._();
  
  static EncryptionService get instance {
    _instance ??= EncryptionService._();
    return _instance!;
  }
  
  String? get publicKey => _publicKey;
  String? get privateKey => _privateKey;
  bool get isInitialized => _isInitialized;
  bool get hasKeys => _privateKey != null && _publicKey != null;
  
  /// Initialize encryption service - load or generate keys
  Future<void> initialize() async {
    if (_isInitialized) {
      print('🔐 Encryption: Already initialized');
      return;
    }
    
    print('══════════════════════════════════════════════════════');
    print('🔐 PARENT APP ENCRYPTION SERVICE - INITIALIZING');
    print('   Device Type: Guardian (Parent)');
    print('══════════════════════════════════════════════════════');
    
    final prefs = await SharedPreferences.getInstance();
    
    // Check if keys already exist
    final keyGenerated = prefs.getBool(_keyGeneratedKey) ?? false;
    print('🔐 Encryption: Checking for existing keys...');
    print('   - Keys Generated Flag: $keyGenerated');
    
    if (keyGenerated) {
      print('🔐 Encryption: Loading existing RSA keys from storage...');
      _privateKey = prefs.getString(_privateKeyKey);
      _publicKey = prefs.getString(_publicKeyKey);
      
      if (_privateKey != null && _publicKey != null) {
        print('══════════════════════════════════════════════════════');
        print('✅ EXISTING RSA KEYS LOADED SUCCESSFULLY');
        print('   Device Type: PARENT (Guardian)');
        print('══════════════════════════════════════════════════════');
        print('🔑 PUBLIC KEY (FULL):');
        print(_publicKey!);
        print('══════════════════════════════════════════════════════');
        print('🔐 PRIVATE KEY (FULL):');
        print(_privateKey!);
        print('══════════════════════════════════════════════════════');
        print('📊 Key Statistics:');
        print('   - Public key length: ${_publicKey!.length} characters');
        print('   - Private key length: ${_privateKey!.length} characters');
        print('   - Key size: 2048-bit RSA');
        print('   - Storage: SharedPreferences');
        print('══════════════════════════════════════════════════════');
        _isInitialized = true;
        return;
      } else {
        print('⚠️ Encryption: Keys corrupted or incomplete, regenerating...');
      }
    }
    
    // Generate new keys
    print('🔐 Encryption: No existing keys found');
    print('🔐 Encryption: Generating new RSA key pair (2048-bit)...');
    await _generateAndStoreKeys();
    _isInitialized = true;
  }
  
  /// Generate new RSA key pair and store locally
  Future<void> _generateAndStoreKeys() async {
    try {
      print('══════════════════════════════════════════════════════');
      print('🔐 GENERATING NEW RSA KEY PAIR');
      print('   Device Type: PARENT (Guardian)');
      print('   Key Size: 2048-bit');
      print('══════════════════════════════════════════════════════');
      
      // Generate RSA key pair using pointycastle
      final secureRandom = FortunaRandom();
      final seedSource = Random.secure();
      final seeds = <int>[];
      for (int i = 0; i < 32; i++) {
        seeds.add(seedSource.nextInt(256));
      }
      secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seeds)));
      
      print('🔐 Step 1/4: Initializing secure random number generator...');
      final rsaKeyGenerator = RSAKeyGenerator()
        ..init(pc.ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
          secureRandom,
        ));
      
      print('🔐 Step 2/4: Generating RSA key pair (this may take a few seconds)...');
      final keyPair = rsaKeyGenerator.generateKeyPair();
      final publicKey = keyPair.publicKey as RSAPublicKey;
      final privateKey = keyPair.privateKey as RSAPrivateKey;
      
      print('🔐 Step 3/4: Converting keys to PEM format...');
      
      // Convert to PEM format
      _publicKey = _encodePublicKeyToPem(publicKey);
      _privateKey = _encodePrivateKeyToPem(privateKey);
      
      print('🔐 Step 4/4: Storing keys securely in SharedPreferences...');
      
      // Store in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_publicKeyKey, _publicKey!);
      await prefs.setString(_privateKeyKey, _privateKey!);
      await prefs.setBool(_keyGeneratedKey, true);
      
      print('══════════════════════════════════════════════════════');
      print('✅ RSA KEY PAIR GENERATED AND STORED SUCCESSFULLY!');
      print('   Device Type: PARENT (Guardian)');
      print('══════════════════════════════════════════════════════');
      print('🔑 PUBLIC KEY (FULL):');
      print(_publicKey!);
      print('══════════════════════════════════════════════════════');
      print('🔐 PRIVATE KEY (FULL):');
      print(_privateKey!);
      print('══════════════════════════════════════════════════════');
      print('📊 Key Statistics:');
      print('   - Public key length: ${_publicKey!.length} characters');
      print('   - Private key length: ${_privateKey!.length} characters');
      print('   - Algorithm: RSA-2048');
      print('   - Format: PEM');
      print('   - Storage: SharedPreferences (persistent)');
      print('   - Next Step: Will upload to server after login');
      print('══════════════════════════════════════════════════════');
      
    } catch (e, stackTrace) {
      print('❌ Encryption: Key generation failed: $e');
      print('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  /// Upload public key to server
  Future<bool> uploadPublicKeyToServer() async {
    if (_publicKey == null) {
      debugPrint('❌ Encryption: No public key to upload');
      return false;
    }
    
    try {
      debugPrint('══════════════════════════════════════════════════════');
      debugPrint('📤 UPLOADING PUBLIC KEY TO SERVER');
      debugPrint('   Device Type: PARENT (Guardian)');
      debugPrint('   Endpoint: /api/mobile/guardian/public-key/');
      debugPrint('══════════════════════════════════════════════════════');
      
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('parent_email') ?? '';
      final password = prefs.getString('parent_password') ?? '';
      debugPrint('📋 Credentials:');
      debugPrint('   - Email: ${email.isEmpty ? "EMPTY" : email}');
      debugPrint('   - Password: ${password.isEmpty ? "EMPTY" : "[PRESENT]"}');
      
      if (email.isEmpty || password.isEmpty) {
        debugPrint('❌ Encryption: Missing credentials - cannot upload');
        return false;
      }
      
      debugPrint('📡 Sending HTTP POST request...');
      final response = await http.post(
        Uri.parse('$baseUrl/api/mobile/guardian/public-key/'),
        headers: {
          'Content-Type': 'application/json',
          'X-Email': email,
          'X-Password': password,
        },
        body: json.encode({
          'public_key': _publicKey,
        }),
      );
      
      debugPrint('📥 Server Response:');
      debugPrint('   - Status Code: ${response.statusCode}');
      debugPrint('   - Response Body: ${response.body}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('══════════════════════════════════════════════════════');
        debugPrint('✅ PUBLIC KEY SUCCESSFULLY UPLOADED TO SERVER!');
        debugPrint('   Device Type: PARENT (Guardian)');
        debugPrint('   Endpoint: $baseUrl/api/mobile/guardian/public-key/update/');
        debugPrint('   Status: ${response.statusCode}');
        debugPrint('   Email: $email');
        debugPrint('   Response: ${response.body}');
        debugPrint('══════════════════════════════════════════════════════');
        return true;
      } else {
        debugPrint('══════════════════════════════════════════════════════');
        debugPrint('❌ PUBLIC KEY UPLOAD FAILED!');
        debugPrint('   Device Type: PARENT (Guardian)');
        debugPrint('   Endpoint: $baseUrl/api/mobile/guardian/public-key/update/');
        debugPrint('   Status: ${response.statusCode}');
        debugPrint('   Email: $email');
        debugPrint('   Response: ${response.body}');
        debugPrint('══════════════════════════════════════════════════════');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Encryption: Upload error: $e');
      return false;
    }
  }
  
  /// Encrypt text using a public key
  String encryptWithPublicKey(String plainText, String publicKeyPem) {
    try {
      final publicKey = encrypt.RSAKeyParser().parse(publicKeyPem) as RSAPublicKey;
      final encrypter = encrypt.Encrypter(encrypt.RSA(publicKey: publicKey));
      final encrypted = encrypter.encrypt(plainText);
      return encrypted.base64;
    } catch (e) {
      debugPrint('❌ Encryption: Encryption error: $e');
      rethrow;
    }
  }
  
  /// Decrypt text using our private key
  String? decryptWithPrivateKey(String encryptedBase64) {
    if (_privateKey == null) {
      debugPrint('❌ Encryption: No private key available for decryption');
      return null;
    }
    
    try {
      final privateKey = encrypt.RSAKeyParser().parse(_privateKey!) as RSAPrivateKey;
      final encrypter = encrypt.Encrypter(encrypt.RSA(privateKey: privateKey));
      final encrypted = encrypt.Encrypted.fromBase64(encryptedBase64);
      return encrypter.decrypt(encrypted);
    } catch (e) {
      debugPrint('❌ Encryption: Decryption error: $e');
      return null;
    }
  }
  
  /// Convert RSA public key to PEM format
  String _encodePublicKeyToPem(RSAPublicKey publicKey) {
    final algorithmSeq = ASN1Sequence();
    final algorithmAsn1Obj = ASN1Object.fromBytes(Uint8List.fromList([0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]));
    final paramsAsn1Obj = ASN1Object.fromBytes(Uint8List.fromList([0x05, 0x00]));
    algorithmSeq.add(algorithmAsn1Obj);
    algorithmSeq.add(paramsAsn1Obj);

    final publicKeySeq = ASN1Sequence();
    publicKeySeq.add(ASN1Integer(publicKey.modulus!));
    publicKeySeq.add(ASN1Integer(publicKey.exponent!));
    final publicKeySeqBitString = ASN1BitString(Uint8List.fromList(publicKeySeq.encodedBytes));

    final topLevelSeq = ASN1Sequence();
    topLevelSeq.add(algorithmSeq);
    topLevelSeq.add(publicKeySeqBitString);

    final dataBase64 = base64.encode(topLevelSeq.encodedBytes);
    return '-----BEGIN PUBLIC KEY-----\n$dataBase64\n-----END PUBLIC KEY-----';
  }
  
  /// Convert RSA private key to PEM format
  String _encodePrivateKeyToPem(RSAPrivateKey privateKey) {
    final topLevelSeq = ASN1Sequence();
    
    final version = ASN1Integer(BigInt.from(0));
    final modulus = ASN1Integer(privateKey.n!);
    final publicExponent = ASN1Integer(BigInt.from(65537));
    final privateExponent = ASN1Integer(privateKey.d!);
    final p = ASN1Integer(privateKey.p!);
    final q = ASN1Integer(privateKey.q!);
    final dP = privateKey.d! % (privateKey.p! - BigInt.one);
    final dQ = privateKey.d! % (privateKey.q! - BigInt.one);
    final iQ = privateKey.q!.modInverse(privateKey.p!);
    
    topLevelSeq.add(version);
    topLevelSeq.add(modulus);
    topLevelSeq.add(publicExponent);
    topLevelSeq.add(privateExponent);
    topLevelSeq.add(p);
    topLevelSeq.add(q);
    topLevelSeq.add(ASN1Integer(dP));
    topLevelSeq.add(ASN1Integer(dQ));
    topLevelSeq.add(ASN1Integer(iQ));

    final dataBase64 = base64.encode(topLevelSeq.encodedBytes);
    return '-----BEGIN RSA PRIVATE KEY-----\n$dataBase64\n-----END RSA PRIVATE KEY-----';
  }
  
  /// Clear all keys (for logout)
  Future<void> clearKeys() async {
    debugPrint('🔐 Encryption: Clearing all keys...');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_privateKeyKey);
    await prefs.remove(_publicKeyKey);
    await prefs.remove(_keyGeneratedKey);
    _privateKey = null;
    _publicKey = null;
    _isInitialized = false;
    debugPrint('✅ Encryption: Keys cleared');
  }
}

// ASN1 Helper Classes for PEM encoding
class ASN1Object {
  int? tag;
  Uint8List? valueBytes;
  
  ASN1Object.fromBytes(Uint8List bytes) {
    if (bytes.length < 2) {
      throw ArgumentError('Invalid ASN1 object');
    }
    tag = bytes[0];
    valueBytes = bytes.sublist(1);
  }
  
  Uint8List get encodedBytes {
    return Uint8List.fromList([tag!, ...valueBytes!]);
  }
}

class ASN1Sequence {
  List<dynamic> elements = [];
  
  void add(dynamic element) {
    elements.add(element);
  }
  
  Uint8List get encodedBytes {
    final valueBytes = <int>[];
    for (final element in elements) {
      if (element is ASN1Sequence || element is ASN1Integer || element is ASN1BitString) {
        valueBytes.addAll(element.encodedBytes);
      } else if (element is ASN1Object) {
        valueBytes.addAll(element.encodedBytes);
      }
    }
    
    final length = valueBytes.length;
    final lengthBytes = <int>[];
    
    if (length < 128) {
      lengthBytes.add(length);
    } else {
      final lengthOfLength = (length.bitLength + 7) ~/ 8;
      lengthBytes.add(0x80 + lengthOfLength);
      for (int i = lengthOfLength - 1; i >= 0; i--) {
        lengthBytes.add((length >> (8 * i)) & 0xFF);
      }
    }
    
    return Uint8List.fromList([0x30, ...lengthBytes, ...valueBytes]);
  }
}

class ASN1Integer {
  BigInt value;
  
  ASN1Integer(this.value);
  
  Uint8List get encodedBytes {
    var bytes = _bigIntToBytes(value);
    
    // Add leading zero if high bit is set
    if (bytes.isNotEmpty && bytes[0] & 0x80 != 0) {
      bytes = Uint8List.fromList([0, ...bytes]);
    }
    
    final length = bytes.length;
    final lengthBytes = <int>[];
    
    if (length < 128) {
      lengthBytes.add(length);
    } else {
      final lengthOfLength = (length.bitLength + 7) ~/ 8;
      lengthBytes.add(0x80 + lengthOfLength);
      for (int i = lengthOfLength - 1; i >= 0; i--) {
        lengthBytes.add((length >> (8 * i)) & 0xFF);
      }
    }
    
    return Uint8List.fromList([0x02, ...lengthBytes, ...bytes]);
  }
  
  Uint8List _bigIntToBytes(BigInt number) {
    if (number == BigInt.zero) return Uint8List.fromList([0]);
    
    final bytes = <int>[];
    var n = number;
    while (n > BigInt.zero) {
      bytes.insert(0, (n & BigInt.from(0xFF)).toInt());
      n = n >> 8;
    }
    return Uint8List.fromList(bytes);
  }
}

class ASN1BitString {
  Uint8List valueBytes;
  
  ASN1BitString(this.valueBytes);
  
  Uint8List get encodedBytes {
    final bytes = [0, ...valueBytes]; // 0 unused bits
    final length = bytes.length;
    final lengthBytes = <int>[];
    
    if (length < 128) {
      lengthBytes.add(length);
    } else {
      final lengthOfLength = (length.bitLength + 7) ~/ 8;
      lengthBytes.add(0x80 + lengthOfLength);
      for (int i = lengthOfLength - 1; i >= 0; i--) {
        lengthBytes.add((length >> (8 * i)) & 0xFF);
      }
    }
    
    return Uint8List.fromList([0x03, ...lengthBytes, ...bytes]);
  }
}
