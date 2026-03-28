import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:guardian_ai/screens/startup_gate_screen.dart';
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

import 'package:guardian_ai/utils/preferences_manager.dart';
import 'package:guardian_ai/utils/app_theme.dart';
import 'package:guardian_ai/utils/app_logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await AppLogger.init();
  AppLogger.log('═══════════════════════════════════════════════════════');
  AppLogger.log('🚀 GUARDIAN AI APP STARTING...');
  AppLogger.log('═══════════════════════════════════════════════════════');

  final prefsManager = await PreferencesManager.init();
  AppLogger.log('✅ PreferencesManager initialized');

  try {
    await EncryptionService.instance.initialize();
    AppLogger.log('✅ Encryption Service initialized');
  } catch (e, st) {
    AppLogger.logError('Encryption init failed', e, st);
  }

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
      runApp(GuardianAIAppWrapper(prefsManager: prefsManager));
    },
    (error, stack) {
      AppLogger.logError('Uncaught zone error', error, stack);
    },
  );
}

class GuardianAIAppWrapper extends StatelessWidget {
  final PreferencesManager prefsManager;
  const GuardianAIAppWrapper({super.key, required this.prefsManager});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guardian AI',
      debugShowCheckedModeBanner: false,
      home: StartupGateScreen(appBuilder: (_) => _buildMainApp()),
    );
  }

  Widget _buildMainApp() {
    Widget initialScreen = const LoginScreen();

    if (prefsManager.isLoggedIn()) {
      final lastRoute = prefsManager.getLastRoute();
      final viewMode = prefsManager.getViewMode();

      if (lastRoute == '/parent_dashboard' || viewMode == 'parent') {
        initialScreen = const ParentDashboardScreen();
      } else if (prefsManager.hasSelectedChild()) {
        initialScreen = const ChildScreen();
      } else {
        initialScreen = const ProfileSelectionScreen();
      }
    }

    return MultiProvider(
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
      child: GuardianAIApp(
        prefsManager: prefsManager,
        initialScreen: initialScreen,
      ),
    );
  }
}

class GuardianAIApp extends StatelessWidget {
  final PreferencesManager prefsManager;
  final Widget initialScreen;

  const GuardianAIApp({
    super.key,
    required this.prefsManager,
    required this.initialScreen,
  });

  @override
  Widget build(BuildContext context) {
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
          ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: BorderSide(color: AppTheme.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: AppTheme.accentBlue),
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
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppTheme.success
                : Colors.grey,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppTheme.success.withOpacity(0.4)
                : Colors.grey.withOpacity(0.3),
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
      },
    );
  }
}
