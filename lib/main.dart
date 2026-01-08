import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/child_screen.dart';
import 'screens/profile_selection_screen.dart';
import 'screens/parent_dashboard_screen.dart';
import 'services/api_service.dart';
import 'services/location_service.dart';
import 'services/websocket_service.dart';
import 'services/app_blocker_service.dart';
import 'services/chat_service.dart';
import 'services/time_extension_service.dart';
import 'services/encryption_service.dart';
import 'utils/preferences_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('═══════════════════════════════════════════════════════');
  print('🚀 GUARDIAN AI APP STARTING...');
  print('═══════════════════════════════════════════════════════');
  
  // Initialize PreferencesManager
  print('📦 Initializing PreferencesManager...');
  final prefsManager = await PreferencesManager.init();
  print('✅ PreferencesManager initialized');
  
  // Initialize Encryption Service (generate/load RSA keys)
  print('🔐 Initializing Encryption Service...');
  try {
    await EncryptionService.instance.initialize();
    print('✅ Encryption Service initialized successfully');
  } catch (e, stackTrace) {
    print('❌ ENCRYPTION SERVICE INITIALIZATION FAILED!');
    print('Error: $e');
    print('Stack trace: $stackTrace');
  }
  print('═══════════════════════════════════════════════════════');

  runApp(
    MultiProvider(
      providers: [
        Provider<PreferencesManager>.value(value: prefsManager),
        Provider<ApiService>(create: (_) => ApiService()),
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => WebSocketService()),
        ChangeNotifierProvider(create: (_) => AppBlockerService()),
        ChangeNotifierProvider(create: (_) => ChatService()),
        ChangeNotifierProvider(create: (_) => TimeExtensionService()),
      ],
      child: GuardianAIApp(prefsManager: prefsManager),
    ),
  );
}

class GuardianAIApp extends StatelessWidget {
  final PreferencesManager prefsManager;
  
  const GuardianAIApp({super.key, required this.prefsManager});

  @override
  Widget build(BuildContext context) {
    // Determine initial route based on login status
    Widget initialScreen = const LoginScreen();
    
    if (prefsManager.isLoggedIn()) {
      final lastRoute = prefsManager.getLastRoute();
      final viewMode = prefsManager.getViewMode();
      
      if (lastRoute == '/parent_dashboard' || viewMode == 'parent') {
        // Parent was viewing parent dashboard
        initialScreen = const ParentDashboardScreen();
      } else if (prefsManager.hasSelectedChild()) {
        // Child screen
        initialScreen = const ChildScreen();
      } else {
        // Logged in but no child selected - go to profile selection
        initialScreen = const LoginScreen();
      }
    }
    
    return MaterialApp(
      title: 'Guardian AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      themeMode: ThemeMode.system,
      home: initialScreen,
      routes: {
        '/login': (context) => const LoginScreen(),
        '/profile_selection': (context) => const ProfileSelectionScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/child': (context) => const ChildScreen(),
        '/parent_dashboard': (context) => const ParentDashboardScreen(),
      },
    );
  }
}
