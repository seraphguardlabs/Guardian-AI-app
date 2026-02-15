import 'dart:async';
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
import 'services/geofence_service.dart';
import 'services/gamified_permission_service.dart';
import 'screens/assign_task_screen.dart';


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

  runApp(GuardianAIAppWrapper());
}

// Wrapper that handles initialization after app starts
class GuardianAIAppWrapper extends StatelessWidget {
  const GuardianAIAppWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guardian AI',
      debugShowCheckedModeBanner: false,
      home: InitializationScreen(),
    );
  }
}

// Screen that performs initialization and then navigates to main app
class InitializationScreen extends StatefulWidget {
  const InitializationScreen({super.key});

  @override
  State<InitializationScreen> createState() => _InitializationScreenState();
}

class _InitializationScreenState extends State<InitializationScreen> {
  String _status = 'Initializing...';
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      setState(() => _status = 'Loading preferences...');
      await Future.delayed(const Duration(milliseconds: 100)); // Let UI update
      
      final prefsManager = await PreferencesManager.init();
      
      setState(() => _status = 'Initializing encryption...');
      await Future.delayed(const Duration(milliseconds: 100));
      
      try {
        await EncryptionService.instance.initialize();
      } catch (e) {
        print('Encryption init failed: $e');
        // Continue anyway
      }
      
      // Successfully initialized - navigate to main app
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MultiProvider(
              providers: [
                Provider<PreferencesManager>.value(value: prefsManager),
                Provider<ApiService>(create: (_) => ApiService()),
                ChangeNotifierProvider(create: (_) => LocationService()),
                ChangeNotifierProvider(create: (_) => WebSocketService()),
                ChangeNotifierProvider(create: (_) => AppBlockerService()),
                ChangeNotifierProvider(create: (_) => ChatService()),
                ChangeNotifierProvider(create: (_) => TimeExtensionService()),
                ChangeNotifierProvider(create: (_) => GeofenceService()),
                ChangeNotifierProvider(create: (_) => GamifiedPermissionService()),
              ],
              child: GuardianAIApp(prefsManager: prefsManager),
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('Initialization error: $e');
      print('Stack: $stackTrace');
      
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _hasError
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 20),
                    const Text(
                      'Initialization Error',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _hasError = false;
                          _errorMessage = '';
                        });
                        _initialize();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const FlutterLogo(size: 100),
                  const SizedBox(height: 30),
                  const CircularProgressIndicator(color: Colors.blue),
                  const SizedBox(height: 20),
                  Text(
                    _status,
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ],
              ),
      ),
    );
  }
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
        initialScreen = const ProfileSelectionScreen();
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
        // '/ai_test': (context) => const AITestScreen(), // Removed
        // '/assign_task': (context) => const AssignTaskScreen(), // Removed due to dependency on child object

      },
    );
  }
}
