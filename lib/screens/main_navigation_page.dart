import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/screens/ac_app/system_view.dart';
import 'package:ir_blaster_ac/screens/ac_app/dashboard_screen.dart';
import 'package:ir_blaster_ac/screens/ac_app/settings_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/ac_control_page.dart';
import 'package:ir_blaster_ac/screens/bluetooth_scanner_page.dart';
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';
import 'package:ir_blaster_ac/screens/widgets/wifi_management_dialog.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/screens/ac_app/admin_panel_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/sigin.dart';

class MainNavigationPage extends StatefulWidget {
  final int initialIndex;
  const MainNavigationPage({super.key, this.initialIndex = 0});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;
  int _systemCount = 0;
  final GlobalKey<SystemViewPageState> _systemViewKey = GlobalKey<SystemViewPageState>();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.backgroundDark : AppColors.background;
    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final subtitleColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Header ──
            _buildHeader(isDark, textColor, subtitleColor),

            // ── Tab Body ──
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  // Tab 0: Systems
                   SystemViewPage(
                    key: _systemViewKey,
                    onCountChanged: (count) =>
                        setState(() => _systemCount = count),
                    onViewPressed: (systemId, systemName, systemShortId) async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ACControlPage(
                            deviceName: systemName,
                            systemId: systemId,
                            systemShortId: systemShortId,
                          ),
                        ),
                      );
                      _systemViewKey.currentState?.refreshData();
                    },
                  ),
                  // Tab 1: Analytics
                  _currentIndex == 1 ? const DashboardScreen() : const SizedBox.shrink(),
                  // Tab 2: Settings
                  const SettingsPage(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(isDark),
    );
  }

  Widget _buildHeader(bool isDark, Color textColor, Color subtitleColor) {
    final titles = ['Systems', 'Energy & Usage Insights', 'Settings'];
    final subtitles = [
      '$_systemCount systems',
      'Monitor your consumption',
      'System configurations',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titles[_currentIndex],
                style: GoogleFonts.outfit(
                  color: textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitles[_currentIndex],
                style: GoogleFonts.inter(
                  color: subtitleColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          Row(
            children: [
              // WiFi Reset Button
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => WifiManagementDialog(
                      mqtt: MqttService(),
                      initialSsid: '',
                    ),
                  );
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : Colors.white,
                    border: Border.all(
                      color: isDark ? AppColors.dividerDark : AppColors.divider,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.wifi_rounded,
                    color: AppColors.offline,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BluetoothScannerPage(),
                    ),
                  );
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : Colors.white,
                    border: Border.all(
                      color: isDark ? AppColors.dividerDark : AppColors.divider,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.bluetooth_searching_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // User Avatar
              GestureDetector(
                onTap: () => _showProfilePopup(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.primaryLight],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool isDark) {
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final borderColor = isDark ? AppColors.dividerDark : AppColors.divider;
    final selectedColor = AppColors.primary;
    final unselectedColor = isDark ? AppColors.textSecondaryDark : AppColors.textHint;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(top: BorderSide(color: borderColor, width: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 0) {
            _systemViewKey.currentState?.refreshData();
          }
          setState(() => _currentIndex = index);
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: selectedColor,
        unselectedItemColor: unselectedColor,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        items: [
          BottomNavigationBarItem(
            icon: _buildNavIcon(Icons.layers_outlined, 0, unselectedColor),
            activeIcon: _buildNavIcon(Icons.layers_rounded, 0, selectedColor),
            label: 'Systems',
          ),
          BottomNavigationBarItem(
            icon: _buildNavIcon(Icons.trending_up_rounded, 1, unselectedColor),
            activeIcon: _buildNavIcon(Icons.trending_up_rounded, 1, selectedColor),
            label: 'Analytics',
          ),
          BottomNavigationBarItem(
            icon: _buildNavIcon(Icons.settings_outlined, 2, unselectedColor),
            activeIcon: _buildNavIcon(Icons.settings_rounded, 2, selectedColor),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildNavIcon(IconData icon, int index, Color color) {
    final isActive = _currentIndex == index;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isActive)
          Container(
            width: 24,
            height: 3,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          )
        else
          const SizedBox(height: 7),
        Icon(icon, color: color, size: 22),
      ],
    );
  }

  void _showProfilePopup(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userData = await AuthService.getUserData();
    final email = await AuthService.getEmail();
    final role = AuthService.roleFromUserData(userData);
    final isAdmin = AuthService.isPlatformAdminRole(role) ||
        AuthService.isCompanyAdminRole(role) ||
        AuthService.isAdminRole(role) ||
        AuthService.isSiteAdminRole(role);

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.2),
      builder: (context) => Stack(
        children: [
          Positioned(
            top: 70,
            right: 20,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 260,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Header
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          child: const Icon(Icons.person_rounded, color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userData?['name'] ?? userData?['Name'] ?? 'User',
                                style: GoogleFonts.poppins(
                                  color: isDark ? Colors.white : const Color(0xFF1B172E),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                email ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  color: (isDark ? Colors.white : const Color(0xFF1B172E)).withOpacity(0.5),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    if (isAdmin) ...[
                      _menuItem(
                        icon: Icons.admin_panel_settings_outlined,
                        label: 'Admin Panel',
                        isDark: isDark,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AdminPanelPage(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Logout Item
                    _menuItem(
                      icon: Icons.logout_rounded,
                      label: 'Logout',
                      isDark: isDark,
                      color: const Color(0xFFEF4444),
                      onTap: () {
                        Navigator.pop(context);
                        _showLogoutDialog(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
    Widget? trailing,
    Color? color,
  }) {
    final baseColor = color ?? (isDark ? Colors.white : const Color(0xFF1B172E));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: baseColor.withOpacity(0.7), size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  color: baseColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => Stack(
        children: [
          AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2D2D44) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              'Logout',
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white : const Color(0xFF1B172E),
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              'Are you sure you want to sign out of your account?',
              style: GoogleFonts.poppins(
                color: (isDark ? Colors.white : const Color(0xFF1B172E)).withOpacity(0.7),
                fontSize: 14,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(
                    color: (isDark ? Colors.white : const Color(0xFF1B172E)).withOpacity(0.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  await AuthService.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const SignInPage()),
                      (route) => false,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Logout'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
