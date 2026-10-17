import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:ir_blaster_ac/core/theme/app_theme.dart';
import 'package:ir_blaster_ac/core/theme/theme_provider.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart' as ac_auth;
import 'package:ir_blaster_ac/screens/ac_app/sigin.dart';
import 'package:ir_blaster_ac/screens/main_navigation_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/splash_screen.dart';
import 'package:ir_blaster_ac/screens/ac_app/platform_admin_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/company_sites_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/company_admin_page.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('⚠️ Firebase Init Error: $e');
  }

  // Initialize Dotenv
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('⚠️ Error loading .env: $e');
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      navigatorKey: ac_auth.AuthService.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'IR Blaster',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late Future<Map<String, dynamic>?> _authFuture;

  @override
  void initState() {
    super.initState();
    _authFuture = _checkAuth();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _authFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ACSplashScreen();
        }

        if (snapshot.hasError) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Scaffold(
            backgroundColor:
                isDark ? AppColors.backgroundDark : AppColors.background,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.offline.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.wifi_off_rounded,
                        color: AppColors.offline, size: 40),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Connection Error',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check your internet connection',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _authFuture = _checkAuth();
                      });
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text('Retry',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Authenticated
        if (snapshot.data != null) {
          final userData = snapshot.data!;
          final role = ac_auth.AuthService.roleFromUserData(userData);

          if (ac_auth.AuthService.isPlatformAdminRole(role)) {
            final companyId = ac_auth.AuthService.extractCompanyId(userData);
            return PlatformAdminPage(companyId: companyId);
          } else if (ac_auth.AuthService.isCompanyAdminRole(role)) {
            return const CompanyAdminPage();
          } else {
            // Employees / technicians with an assigned site go straight to dashboard
            final siteId =
                userData['site']?.toString() ?? userData['siteId']?.toString();
            if (siteId != null && siteId.isNotEmpty) {
              return const MainNavigationPage();
            }
            final companyId = ac_auth.AuthService.extractCompanyId(userData);
            final companyName =
                ac_auth.AuthService.extractCompanyName(userData) ??
                    'Company Dashboard';
            final bucket = ac_auth.AuthService.extractBucket(userData) ?? '';
            return CompanySitesPage(
              companyId: companyId ?? '',
              companyName: companyName,
              bucket: bucket,
            );
          }
        }

        // Not authenticated
        return const SignInPage();
      },
    );
  }

  Future<Map<String, dynamic>?> _checkAuth() async {
    final startTime = DateTime.now();

    Map<String, dynamic>? result;
    final cachedUser = await ac_auth.AuthService.getUserData();
    if (cachedUser != null) {
      // ignore: unawaited_futures
      ac_auth.AuthService.verify();
      result = cachedUser;
    } else if (await ac_auth.AuthService.hasStoredSession()) {
      result = await ac_auth.AuthService.verify();
    }

    // Ensure splash screen is visible for at least 2.5 seconds
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    if (elapsed < 2500) {
      await Future.delayed(Duration(milliseconds: 2500 - elapsed));
    }

    return result;
  }
}
