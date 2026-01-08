# Guardian AI - Developer Quick Reference

## 🚀 Quick Start

```bash
# Get dependencies
flutter pub get

# Run app
flutter run

# Run tests
flutter test

# Build release
flutter build apk --release
```

## 📁 Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/                   # Data models
├── screens/                  # UI screens
├── services/                 # Business logic
├── widgets/                  # Reusable components
└── utils/                    # Utilities
```

## 🎨 Design Tokens

```dart
// Colors
Color primaryBlue    = Color(0xFF1A3C8B);
Color background     = Color(0xFF0F0F0F);
Color cardBg         = Color(0xFF1A1A1A);

// Spacing
const double small   = 8.0;
const double medium  = 16.0;
const double large   = 24.0;

// Border Radius
const double buttonRadius = 12.0;
const double cardRadius   = 16.0;
```

## 🔌 API Endpoints

### Base URL
```
https://seraphguardlabs.com
```

### Authentication
```dart
// Login
POST /api/login/
Headers: { Content-Type: application/json }
Body: { email, password }

// Get children
GET /api/mobile/children/
Headers: { X-Email, X-Password }
```

### Child Data
```dart
// Screen time
GET /api/mobile/child/<hash>/screen-time/
Params: { start_date, end_date }

// Metrics
GET /api/mobile/child/<hash>/metrics/

// App usage
GET /api/mobile/child/<hash>/app-usage/

// Locations
GET /api/mobile/child/<hash>/locations/
Params: { start_time, end_time, limit }
```

## 🔐 Security

### Encryption Example
```dart
// Initialize (done in main.dart)
final encryptionService = EncryptionService();
await encryptionService.init();

// Encrypt
String encrypted = encryptionService.encrypt(message);

// Decrypt
String decrypted = encryptionService.decrypt(encrypted);
```

### Storage
```dart
// Get instance
final prefs = await PreferencesManager.init();

// Store credentials
await prefs.setParentEmail('parent@example.com');
await prefs.setParentPassword('password123');

// Retrieve
final email = prefs.getParentEmail();
final password = prefs.getParentPassword();
```

## 🔄 State Management

### Provider Setup (in main.dart)
```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ApiService()),
    ChangeNotifierProvider(create: (_) => WebSocketService()),
    ChangeNotifierProvider(create: (_) => TimeExtensionService()),
    // ... more providers
  ],
  child: MyApp(),
)
```

### Using Providers
```dart
// In a widget
final apiService = Provider.of<ApiService>(context);

// Or with Consumer
Consumer<TimeExtensionService>(
  builder: (context, service, child) {
    return Text('Pending: ${service.pendingRequests.length}');
  },
)
```

## 📊 Common Patterns

### Loading State
```dart
bool _isLoading = false;

void _fetchData() async {
  setState(() => _isLoading = true);
  try {
    final data = await apiService.getData();
    // Handle data
  } finally {
    setState(() => _isLoading = false);
  }
}

@override
Widget build(BuildContext context) {
  if (_isLoading) {
    return Center(child: CircularProgressIndicator());
  }
  return YourContent();
}
```

### Error Handling
```dart
try {
  final result = await apiService.login(email, password);
  if (result['success']) {
    // Handle success
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result['error'])),
    );
  }
} catch (e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Error: $e')),
  );
}
```

### Navigation
```dart
// Push named route
Navigator.pushReplacementNamed(context, '/parent-dashboard');

// Pop
Navigator.pop(context);

// With arguments
Navigator.pushNamed(
  context,
  '/child-screen',
  arguments: {'childHash': childHash},
);
```

## 🎯 Common Tasks

### Adding a New Screen

1. Create file in `lib/screens/`
```dart
// lib/screens/new_screen.dart
import 'package:flutter/material.dart';

class NewScreen extends StatefulWidget {
  @override
  _NewScreenState createState() => _NewScreenState();
}

class _NewScreenState extends State<NewScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('New Screen')),
      body: Center(child: Text('Content')),
    );
  }
}
```

2. Add route in `main.dart`
```dart
MaterialApp(
  routes: {
    '/new-screen': (context) => NewScreen(),
    // ... other routes
  },
)
```

### Adding a New API Endpoint

In `lib/services/api_service.dart`:
```dart
Future<Map<String, dynamic>> newEndpoint({
  required String childHash,
  Map<String, String>? params,
}) async {
  final email = await PreferencesManager.getEmail();
  final password = await PreferencesManager.getPassword();
  
  final uri = Uri.parse('$baseUrl/api/mobile/child/$childHash/endpoint/');
  final uriWithParams = params != null 
      ? uri.replace(queryParameters: params) 
      : uri;
  
  try {
    final response = await http.get(
      uriWithParams,
      headers: {
        'X-Email': email ?? '',
        'X-Password': password ?? '',
      },
    );
    
    if (response.statusCode == 200) {
      return {
        'success': true,
        'data': jsonDecode(response.body),
      };
    } else {
      return {
        'success': false,
        'error': 'Request failed',
      };
    }
  } catch (e) {
    return {
      'success': false,
      'error': 'Network error: $e',
    };
  }
}
```

### Creating a New Model

```dart
// lib/models/new_model.dart
class NewModel {
  final String id;
  final String name;
  final DateTime createdAt;
  
  NewModel({
    required this.id,
    required this.name,
    required this.createdAt,
  });
  
  factory NewModel.fromJson(Map<String, dynamic> json) {
    return NewModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
```

## 🐛 Debugging Tips

### View Console Logs
```bash
flutter run --verbose
```

### Network Debugging
```dart
// In api_service.dart
debugPrint('📤 Request: $url');
debugPrint('📥 Response: ${response.body}');
```

### State Debugging
```dart
// Add to stateful widgets
@override
void didUpdateWidget(covariant OldWidget oldWidget) {
  super.didUpdateWidget(oldWidget);
  debugPrint('Widget updated: ${widget.toString()}');
}
```

## 📦 Dependencies Reference

```yaml
# State Management
provider: ^6.0.5

# Networking
http: ^1.1.0
web_socket_channel: ^3.0.1

# Storage
shared_preferences: ^2.2.0

# Encryption
pointycastle: ^3.9.1
encrypt: ^5.0.3

# Charts
fl_chart: ^0.63.0

# Utilities
intl: ^0.18.1           # Date formatting
geolocator: ^10.1.0     # Location
permission_handler: ^11.0.1
usage_stats: ^1.2.0     # Screen time
device_apps: ^2.2.0     # App list
```

## 🧪 Testing Examples

### Unit Test
```dart
// test/models/child_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Child Model', () {
    test('should create from JSON', () {
      final json = {
        'child_hash': 'abc123',
        'first_name': 'John',
        'last_name': 'Doe',
      };
      
      final child = Child.fromJson(json);
      
      expect(child.childHash, 'abc123');
      expect(child.fullName, 'John Doe');
    });
  });
}
```

### Widget Test
```dart
// test/widgets/app_bottom_nav_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('AppBottomNav displays correctly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(
            currentIndex: 0,
            onTap: (index) {},
          ),
        ),
      ),
    );
    
    expect(find.byType(AppBottomNav), findsOneWidget);
  });
}
```

## 🔗 Useful Commands

```bash
# Format code
flutter format .

# Analyze code
flutter analyze

# Clean build
flutter clean

# Get dependencies
flutter pub get

# Check outdated packages
flutter pub outdated

# Update dependencies
flutter pub upgrade

# Generate icons
flutter pub run flutter_launcher_icons:main

# Build APK
flutter build apk --release

# Build App Bundle
flutter build appbundle --release

# Install on device
flutter install

# View connected devices
flutter devices
```

## 📚 Documentation Links

- **Main Docs**: [ARCHITECTURE_DOCS.md](ARCHITECTURE_DOCS.md)
- **Improvements**: [CODE_IMPROVEMENTS.md](CODE_IMPROVEMENTS.md)
- **Review**: [CODE_REVIEW_SUMMARY.md](CODE_REVIEW_SUMMARY.md)
- **Example Screen**: [WEEKLY_ACTIVITY_SCREEN_DOCS.md](lib/screens/WEEKLY_ACTIVITY_SCREEN_DOCS.md)

## ❓ Common Questions

**Q: How do I add a new child profile?**
A: Child profiles are managed on the backend. Parents log in and see their children automatically.

**Q: How does encryption work?**
A: RSA 2048-bit keys are generated on first app launch and stored locally. Messages are encrypted before sending.

**Q: How to test on real device?**
A: `flutter run` with device connected via USB or wirelessly.

**Q: How to change API URL?**
A: Update `baseUrl` in `lib/services/api_service.dart`

**Q: How to add new permissions?**
A: Update `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist`

## 🎨 UI Component Examples

### Gradient Card
```dart
Container(
  padding: EdgeInsets.all(20),
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF1A3C8B), Color(0xFF0D1F4A)],
    ),
    borderRadius: BorderRadius.circular(16),
  ),
  child: Text('Content'),
)
```

### Loading Button
```dart
ElevatedButton(
  onPressed: _isLoading ? null : _handleSubmit,
  child: _isLoading
      ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Text('Submit'),
)
```

## 🚨 Troubleshooting

### "Package not found"
```bash
flutter pub get
flutter clean
flutter pub get
```

### "Build failed"
```bash
flutter clean
rm -rf build/
flutter run
```

### "WebSocket won't connect"
- Check network connection
- Verify childHash is correct
- Check console for errors
- Ensure backend is running

### "Data not refreshing"
- Check API credentials in SharedPreferences
- Verify API endpoint is correct
- Check network tab in debugger

---

**Last Updated**: January 8, 2026
**For detailed documentation**: See [ARCHITECTURE_DOCS.md](ARCHITECTURE_DOCS.md)
