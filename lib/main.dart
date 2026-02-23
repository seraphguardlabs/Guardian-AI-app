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
import 'utils/app_theme.dart';
import 'services/geofence_service.dart';
import 'services/gamified_permission_service.dart';


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

class _InitializationScreenState extends State<InitializationScreen>
    with SingleTickerProviderStateMixin {
  String _status = 'Initializing...';
  bool _hasError = false;
  String _errorMessage = '';
  late final AnimationController _logoController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoScale = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack));
    _logoOpacity = CurvedAnimation(parent: _logoController, curve: Curves.easeOut);
    _logoController.forward();
    _initialize();
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
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
      backgroundColor: AppTheme.background,
      body: AnimatedGradientBg(
        child: Center(
          child: _hasError
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
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
                      const SizedBox(height: 24),
                      TapBounce(
                        onTap: () {
                          setState(() {
                            _hasError = false;
                            _errorMessage = '';
                          });
                          _initialize();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                          decoration: BoxDecoration(
                            gradient: AppTheme.blueGrad,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Retry',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FadeTransition(
                      opacity: _logoOpacity,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withOpacity(0.4),
                                blurRadius: 32,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/shield_logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: AppTheme.primary,
                        strokeWidth: 2.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _status,
                        key: ValueKey(_status),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white54,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
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
        colorScheme: const ColorScheme.dark(
          primary: AppTheme.primary,
          secondary: AppTheme.accent,
          surface: AppTheme.surface,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: AppTheme.background,
        cardTheme: CardThemeData(
          elevation: 4,
          color: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: AppTheme.surface,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: AppTheme.surface,
          contentTextStyle: TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            elevation: 0,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppTheme.surfaceDark,
          labelStyle: const TextStyle(color: Colors.white60),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primary, width: 2),
          ),
        ),
      ),
      themeMode: ThemeMode.dark,
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
