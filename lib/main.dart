import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';

import 'package:guardian_ai/screens/login_screen.dart';
import 'package:guardian_ai/screens/dashboard_screen.dart';
import 'package:guardian_ai/screens/child_screen.dart';
import 'package:guardian_ai/screens/profile_selection_screen.dart';
import 'package:guardian_ai/screens/parent_dashboard_screen.dart';

import 'package:guardian_ai/services/api_service.dart';
import 'package:guardian_ai/services/location_service.dart';
import 'package:guardian_ai/services/websocket_service.dart';
import 'package:guardian_ai/services/app_blocker_service.dart';
import 'package:guardian_ai/services/chat_service.dart';
import 'package:guardian_ai/services/time_extension_service.dart';
import 'package:guardian_ai/services/encryption_service.dart';
import 'package:guardian_ai/services/geofence_service.dart';
import 'package:guardian_ai/services/gamified_permission_service.dart';
import 'package:guardian_ai/services/gemma_content_analyzer.dart';
import 'package:guardian_ai/services/gemma_manager.dart';

import 'package:guardian_ai/utils/preferences_manager.dart';
import 'package:guardian_ai/utils/app_theme.dart';
import 'package:guardian_ai/models/content_analysis_result.dart';
import 'package:guardian_ai/utils/app_logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  
  // Initialize AppLogger
  await AppLogger.init();
  AppLogger.log('═══════════════════════════════════════════════════════');
  AppLogger.log('🚀 GUARDIAN AI APP STARTING...');
  AppLogger.log('═══════════════════════════════════════════════════════');
  
  // Initialize PreferencesManager
  AppLogger.log('📦 Initializing PreferencesManager...');
  final prefsManager = await PreferencesManager.init();
  AppLogger.log('✅ PreferencesManager initialized');
  
  try {
    await EncryptionService.instance.initialize();
    AppLogger.log('✅ Encryption Service initialized successfully');
  } catch (e, stackTrace) {
    AppLogger.logError('ENCRYPTION SERVICE INITIALIZATION FAILED!', e, stackTrace);
  }
  
  // Initialize Background Service
  AppLogger.log('🔄 Initializing Background Service...');
  await initializeBackgroundService();
  AppLogger.log('✅ Background Service initialized');
  
  AppLogger.log('═══════════════════════════════════════════════════════');

  runZonedGuarded(
    () {
      FlutterError.onError = (details) {
        AppLogger.logError(
          'FlutterError',
          details.exceptionAsString(),
          details.stack,
        );
      };
      runApp(GuardianAIAppWrapper());
    },
    (error, stack) {
      AppLogger.logError('Uncaught zone error', error, stack);
    },
  );
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
      try {
        await EncryptionService.instance.initialize();
      } catch (e) {
        print('Encryption init failed: $e');
      }
      
      setState(() => _status = 'Initializing AI safety...');
      await GemmaManager.instance.initialize();
      
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
          error: AppTheme.error,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white,
          onError: Colors.white,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: AppTheme.background,
        cardTheme: CardThemeData(
          elevation: 0,
          color: AppTheme.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: AppTheme.surface,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusXL)),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppTheme.surface,
          contentTextStyle: const TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusM)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: BorderSide(color: AppTheme.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusM)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.accentBlue,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppTheme.surfaceDark,
          labelStyle: const TextStyle(color: Colors.white60),
          hintStyle: const TextStyle(color: AppTheme.textHint),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
            borderSide: const BorderSide(color: AppTheme.primary, width: 2),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppTheme.border,
          thickness: 1,
          space: 1,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppTheme.primary,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AppTheme.success : Colors.grey),
          trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
              ? AppTheme.success.withOpacity(0.4)
              : Colors.grey.withOpacity(0.3)),
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
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Background Service Setup
// ---------------------------------------------------------------------------

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'monitoring_foreground',
    'Guardian AI Monitoring',
    description: 'Running safety analysis in background',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'monitoring_foreground',
      initialNotificationTitle: 'Guardian AI Active',
      initialNotificationContent: 'Monitoring child activity',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async => true;

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  
  await AppLogger.init();
  AppLogger.log('[BG] Background Service onStart initialized');

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) => service.setAsForegroundService());
    service.on('setAsBackground').listen((_) => service.setAsBackgroundService());
  }

  service.on('stopService').listen((_) => service.stopSelf());

  final notifications = FlutterLocalNotificationsPlugin();
  
  const platform = MethodChannel('com.example.guardian_ai/screen_capture');
  InferenceModel? model;
  GemmaContentAnalyzer? analyzer;

  // Background monitoring interval (5 seconds)
  Timer.periodic(const Duration(seconds: 5), (timer) async {
    try {
      if (analyzer == null) {
        // Ensure Gemma is initialized in this isolate
        await GemmaManager.instance.initialize();
        if (await GemmaManager.instance.isModelInstalled() && FlutterGemma.hasActiveModel()) {
          model = await FlutterGemma.getActiveModel(
            maxTokens: 1024,
            supportImage: true,
          );
          analyzer = GemmaContentAnalyzer(model!);
          AppLogger.log('[BG] Gemma model initialized in isolate');
        } else {
          AppLogger.log('[BG] Model not ready yet, skipping capture');
          return;
        }
      }

      // Read newest screenshot from cache
      final dir = await getTemporaryDirectory();
      final screenshotsDir = Directory('${dir.path}/screenshots');
      if (!screenshotsDir.existsSync()) return;
      
      final files = screenshotsDir.listSync().whereType<File>().toList();
      if (files.isEmpty) return;
      
      // Sort to get the newest file
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final latestScreenshot = files.first;
      
      final Uint8List imageBytes = await latestScreenshot.readAsBytes();
      
      // Zero-cache policy: delete immediately after reading
      await latestScreenshot.delete();

      if (analyzer != null) {
        AppLogger.log('[BG] Triggering analysis for screenshot: ${latestScreenshot.path}');
        final result = await analyzer!.analyzeImage(imageBytes);
        
        if (result.riskScore >= 70) {
          AppLogger.log('[BG] 🚨 HIGH RISK DETECTED (${result.riskScore}%)! Categories: ${result.categories.toString()}');
          // Trigger Notification
          await notifications.show(
            999,
            '🚨 Safety Alert: ${result.riskScore}% Risk',
            'Detected ${result.categories.entries.where((e) => e.value > 0.5).map((e) => e.key).join(", ")} content.',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'alerts_channel',
                'Safety Alerts',
                importance: Importance.high,
                priority: Priority.high,
                ticker: 'Safety Alert',
              ),
            ),
          );

          // Notify UI
          service.invoke('alertGenerated', result.toJson());
        }
      }
    } catch (e) {
      AppLogger.log('[BG] Error in monitoring cycle: $e');
    }
  });
}
