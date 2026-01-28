# Guardian AI Mobile App - Complete Documentation

## 📱 Project Overview

Guardian AI is a comprehensive parental control and child safety mobile application built with Flutter. It enables parents to monitor their children's device usage, set screen time limits, block apps, track location, and maintain encrypted communication.

### Key Features
- 👨‍👩‍👧 Parent and child dashboards
- ⏱️ Screen time monitoring and limits
- 🚫 App blocking and exam mode
- 📍 Location tracking
- 💬 Encrypted chat communication
- 🔔 Time extension request system
- 📊 Weekly activity analytics
- 🔐 End-to-end encryption (RSA 2048-bit)

## 🏗️ Architecture

### App Structure
```
lib/
├── main.dart                    # Entry point, providers, routing
├── models/                      # Data models
│   ├── child.dart              # Child profile model
│   ├── time_extension_request.dart
│   ├── restrictions_data.dart
│   ├── chat_message.dart
│   └── websocket_data.dart
├── screens/                     # UI screens
│   ├── login_screen.dart
│   ├── profile_selection_screen.dart
│   ├── parent_dashboard_screen.dart
│   ├── child_screen.dart
│   ├── weekly_activity_screen.dart
│   └── ...
├── services/                    # Business logic & API
│   ├── api_service.dart        # REST API client
│   ├── websocket_service.dart  # WebSocket client
│   ├── encryption_service.dart # RSA encryption
│   ├── app_blocker_service.dart
│   ├── time_extension_service.dart
│   └── ...
├── widgets/                     # Reusable components
│   └── app_bottom_nav.dart
└── utils/                       # Utilities
    └── preferences_manager.dart
```

### State Management
- **Provider Pattern**: Used for dependency injection and state management
- **ChangeNotifier**: Services notify listeners of state changes
- **SharedPreferences**: Local persistent storage

### Network Architecture
- **REST API**: Primary data fetching via ApiService
- **WebSocket**: Real-time updates for time extensions and restrictions
- **Header Auth**: X-Email and X-Password headers for authentication

## 🎨 Design System

### Color Palette
```dart
Primary Background:    #0F0F0F (near black)
Card Background:       #1A1A1A (dark gray)
Primary Accent:        #1A3C8B (navy blue)
Secondary Accent:      #2196F3 (bright blue)
Success:               #4CAF50 (green)
Warning:               #FF9800 (orange)
Error:                 #F44336 (red)
Text Primary:          #FFFFFF (white)
Text Secondary:        #FFFFFF70 (70% white)
```

### Typography
- Titles: 20-32px, FontWeight.bold
- Body: 14-16px, FontWeight.normal
- Captions: 12-14px, FontWeight.normal
- Font: System default (San Francisco/Roboto)

### Spacing
- Small: 8px
- Medium: 16px
- Large: 24px
- XLarge: 32px

### Border Radius
- Cards: 16-20px
- Buttons: 12px
- Input fields: 12px

## 📊 Data Flow

### Parent Login Flow
```
1. LoginScreen -> Enter credentials
2. ApiService.login() -> POST /api/mobile/children/
3. Save credentials to PreferencesManager
4. Initialize EncryptionService (RSA keys)
5. Navigate to ProfileSelectionScreen
6. Select Parent Dashboard or Child Profile
7. Set viewMode and lastRoute in preferences
```

### Child Monitoring Flow
```
1. Child device runs background service
2. RealtimeDataCollector gathers data (screen time, locations, apps)
3. WebSocket connection sends data to server
4. Parent dashboard pulls data via REST API
5. Real-time updates via WebSocket subscriptions
```

### Time Extension Flow
```
Child Side:
1. App limit reached -> Show extension dialog
2. TimeExtensionService.sendRequest()
3. WebSocket message to guardian
4. Listen for response

Parent Side:
1. Receive WebSocket notification
2. Show SnackBar with request details
3. Approve/Deny in TimeExtensionService
4. WebSocket message back to child
5. Update app limits if approved
```

## 🔐 Security

### Encryption
- **Algorithm**: RSA 2048-bit
- **Key Storage**: SharedPreferences (local device)
- **Key Generation**: On first app launch
- **Public Key Upload**: To server for communication
- **Message Encryption**: End-to-end for chats and time extension requests

### Authentication
- **Method**: Header-based (X-Email, X-Password)
- **Storage**: Encrypted in SharedPreferences
- **Session**: Persistent until logout
- **Token**: Optional JWT token support

### Data Protection
- Sensitive data never logged in production
- HTTPS for all API calls
- WSS for WebSocket connections
- No plaintext password storage

## 📡 API Integration

### Base URL
```dart
https://seraphguardlabs.com
```

### Key Endpoints

#### Authentication
- `POST /api/mobile/children/` - Login and get child list
  - Headers: X-Email, X-Password
  - Response: List of Child objects

#### Child Data
- `GET /api/mobile/child/<hash>/metrics/` - Aggregated stats
- `GET /api/mobile/child/<hash>/screen-time/` - Screen time trends
- `GET /api/mobile/child/<hash>/app-usage/` - App usage breakdown
- `GET /api/mobile/child/<hash>/locations/` - Location history
- `GET /api/mobile/child/<hash>/exam-mode/` - Exam mode settings
- `POST /api/mobile/child/<hash>/exam-mode/` - Update exam mode

#### Time Extensions
- `GET /api/mobile/time-extension-requests/` - Get pending requests
- `POST /api/mobile/time-extension-requests/<id>/respond/` - Respond to request

### WebSocket Events
- `wss://seraphguardlabs.com/ws/guardian/time-extension/` - Parent connection
- `wss://seraphguardlabs.com/ws/child/<hash>/time-extension/` - Child connection

## 🧩 Core Components

### Models

#### Child
```dart
class Child {
  final String childHash;      // Unique identifier
  final String firstName;
  final String lastName;
  final String? profileImageUrl;
}
```

#### TimeExtensionRequest
```dart
class TimeExtensionRequest {
  final int requestId;
  final String childHash;
  final String appDomain;
  final double requestedHours;
  final String status;         // pending/approved/denied
  final String? messageEncrypted;
  // ... more fields
}
```

### Services

#### ApiService
- Handles all HTTP requests
- Automatic header injection
- Response parsing
- Error handling

#### WebSocketService
- Maintains persistent connections
- Auto-reconnect logic
- Message routing
- Event streaming

#### EncryptionService (Singleton)
- RSA key pair generation
- Message encryption/decryption
- Public key management
- Key persistence

#### TimeExtensionService
- Request creation and management
- WebSocket integration
- Stream-based notifications
- Response handling

#### AppBlockerService
- Usage stats collection
- App time limit enforcement
- Real-time blocking
- Exam mode support

### Screens

#### LoginScreen
- Email/password input
- Shield logo branding
- Dialog-based login form
- Credential validation
- Auto-navigation on success

#### ParentDashboardScreen
- Child selection
- Today's screen time
- Weekly metrics
- Time extension notifications
- App usage overview
- Location tracking
- Exam mode toggle

#### ChildScreen
- Current screen time
- App time limits
- Blocked apps indicator
- Time extension requests
- Exam mode visual alerts

#### WeeklyActivityScreen
- 3-week comparison chart
- Line graph visualization
- Today's usage summary
- Weekly totals
- Pull-to-refresh

## 🛠️ Development

### Prerequisites
```bash
Flutter SDK: ^3.10.3
Dart SDK: ^3.10.3
```

### Dependencies
```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.0.5
  http: ^1.1.0
  shared_preferences: ^2.2.0
  fl_chart: ^0.63.0
  web_socket_channel: ^3.0.1
  pointycastle: ^3.9.1
  encrypt: ^5.0.3
  intl: ^0.18.1
  geolocator: ^10.1.0
  permission_handler: ^11.0.1
  usage_stats: ^1.2.0
  device_apps: ^2.2.0
```

### Running the App
```bash
# Development
flutter run

# Release build
flutter build apk --release
flutter build ios --release
```

### Testing
```bash
flutter test
flutter test --coverage
```

## 🐛 Common Issues & Solutions

### Issue: Login not persisting
**Solution**: Check that PreferencesManager is properly saving credentials and viewMode

### Issue: WebSocket disconnects
**Solution**: Implement reconnection logic with exponential backoff

### Issue: Screen time not updating
**Solution**: Verify background service is running and has necessary permissions

### Issue: Encryption errors
**Solution**: Clear app data to regenerate keys, or check key format

## 📈 Performance Optimization

### Best Practices
1. **Lazy Loading**: Load data only when needed
2. **Caching**: Store API responses temporarily
3. **Pagination**: Use limit parameters for large datasets
4. **Image Optimization**: Use cached_network_image for profile pictures
5. **Debouncing**: Limit API calls on rapid user actions

### Memory Management
- Dispose controllers in screen lifecycle
- Cancel stream subscriptions
- Close WebSocket connections
- Clear large lists when not needed

## 🔮 Future Enhancements

### Planned Features
- [ ] Push notifications (FCM)
- [ ] In-app purchases for premium features
- [ ] Multi-language support (i18n)
- [ ] Dark/light theme toggle
- [ ] Biometric authentication
- [ ] Export reports as PDF
- [ ] App usage insights with AI
- [ ] Geofencing alerts
- [ ] Content filtering
- [ ] Multiple guardian support

### Technical Debt
- [ ] Migrate to Riverpod for state management
- [ ] Add comprehensive unit tests
- [ ] Implement integration tests
- [ ] Add error tracking (Sentry/Firebase Crashlytics)
- [ ] Performance monitoring
- [ ] Code coverage > 80%
- [ ] Documentation for all public APIs

## 📚 Resources

### Flutter Documentation
- [Flutter Docs](https://docs.flutter.dev/)
- [Dart Docs](https://dart.dev/guides)
- [Provider Package](https://pub.dev/packages/provider)

### API Documentation
- See: `parents_mobile_app_api_guide4.md`
- WebSocket protocol details in `WEBSOCKET_*.md` files

### Project Documentation
- Weekly Activity Screen: `lib/screens/WEEKLY_ACTIVITY_SCREEN_DOCS.md`
- Main README: `README.md`

## 👥 Team & Support

### Development Team
- Mobile Developer: Flutter/Dart specialist
- Backend Developer: Django/Python API
- UI/UX Designer: Mobile-first design

### Support
- Email: support@seraphguardlabs.com
- Documentation: See project wiki
- Issues: GitHub issues page

## 📄 License

Proprietary - All rights reserved
© 2026 Seraph Guard Labs

---

**Version**: 1.0.0
**Last Updated**: January 8, 2026
**Author**: Guardian AI Development Team
