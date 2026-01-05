/// Quick script to clear stored encryption keys
/// Run with: dart run clear_keys.dart
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  print('🔐 Clearing encryption keys...');
  
  final prefs = await SharedPreferences.getInstance();
  
  await prefs.remove('guardian_private_key');
  await prefs.remove('guardian_public_key');
  await prefs.remove('guardian_key_generated');
  
  print('✅ Keys cleared! Next app launch will generate new keys.');
}
