import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/roi_config_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/camera_calibration_screen.dart';
import 'screens/camera_depth_calibration_screen.dart';
import 'screens/roi_editor_screen.dart';
import 'screens/viewer_screen.dart';
import 'services/frame_receiver_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final packageInfo = await PackageInfo.fromPlatform();
  final appTitle = 'CatchEye Studio v${packageInfo.version}';
  await _configureDesktopWindow(appTitle);
  final settingsProvider = await SettingsProvider.load();
  runApp(
    CatchEyeStudioApp(settingsProvider: settingsProvider, appTitle: appTitle),
  );
}

Future<void> _configureDesktopWindow(String appTitle) async {
  if (!Platform.isMacOS && !Platform.isLinux && !Platform.isWindows) {
    return;
  }

  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(1180, 720));
  await windowManager.setSize(const Size(1440, 900));
  await windowManager.center();
  await windowManager.setTitle(appTitle);
}

class CatchEyeStudioApp extends StatelessWidget {
  const CatchEyeStudioApp({
    super.key,
    required this.settingsProvider,
    required this.appTitle,
  });

  final SettingsProvider settingsProvider;
  final String appTitle;

  @override
  Widget build(BuildContext context) {
    const brandTeal = Color(0xFF006E7A);
    const brandTealLight = Color(0xFF73D4DC);
    const brandOrange = Color(0xFFFF7A2F);
    const appBackground = Color(0xFF071011);
    const appSurface = Color(0xFF101B1D);
    const appSurfaceHigh = Color(0xFF172A2D);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => RoiConfigProvider()..tryLoadDefault(),
        ),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider(create: (_) => FrameReceiverService()),
      ],
      child: MaterialApp(
        title: appTitle,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: appBackground,
          colorScheme: const ColorScheme.dark(
            primary: brandTealLight,
            onPrimary: Color(0xFF062426),
            primaryContainer: brandTeal,
            onPrimaryContainer: Colors.white,
            secondary: brandOrange,
            onSecondary: Color(0xFF241005),
            surface: appSurface,
            onSurface: Color(0xFFEAF2F2),
            surfaceContainerHighest: appSurfaceHigh,
            outline: Color(0xFF3E5559),
          ),
          dividerColor: const Color(0xFF30474B),
          useMaterial3: true,
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: brandTealLight,
              foregroundColor: const Color(0xFF062426),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: brandTealLight,
              side: const BorderSide(color: Color(0xFF5E858A)),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          navigationRailTheme: const NavigationRailThemeData(
            backgroundColor: appSurface,
            indicatorColor: Color(0xFF23474D),
            selectedIconTheme: IconThemeData(color: brandTealLight),
            selectedLabelTextStyle: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            unselectedIconTheme: IconThemeData(color: Color(0xFFA8B9BC)),
            unselectedLabelTextStyle: TextStyle(
              color: Color(0xFFA8B9BC),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _items = [
    _NavItem(
      label: 'Viewer',
      icon: Icons.live_tv_outlined,
      selectedIcon: Icons.live_tv,
    ),
    _NavItem(
      label: 'ROI Editor',
      icon: Icons.edit_location_alt_outlined,
      selectedIcon: Icons.edit_location_alt,
    ),
    _NavItem(
      label: 'Camera Calibration',
      icon: Icons.grid_on_outlined,
      selectedIcon: Icons.grid_on,
    ),
    _NavItem(
      label: 'Depth Calibration',
      icon: Icons.threed_rotation_outlined,
      selectedIcon: Icons.threed_rotation,
    ),
  ];

  static const _screens = [
    ViewerScreen(),
    RoiEditorScreen(),
    CameraCalibrationScreen(),
    CameraDepthCalibrationScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _AppSidebar(
            selectedIndex: _selectedIndex,
            items: _items,
            onSelected: (index) {
              if (index >= 2) {
                unawaited(context.read<FrameReceiverService>().disconnect());
              }
              setState(() => _selectedIndex = index);
            },
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _screens[_selectedIndex]),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _AppSidebar extends StatelessWidget {
  const _AppSidebar({
    required this.selectedIndex,
    required this.items,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<_NavItem> items;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 224,
      color: const Color(0xFF101B1D),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 52,
                  height: 52,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F6F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF73D4DC)),
                  ),
                  child: Image.asset('assets/emblem.png', fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 18),
              for (var i = 0; i < items.length; i++) ...[
                _SidebarButton(
                  item: items[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelected(i),
                ),
                const SizedBox(height: 6),
              ],
              const Spacer(),
              Image.asset('assets/logo.png', height: 34, fit: BoxFit.contain),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = selected
        ? const Color(0xFF73D4DC)
        : const Color(0xFFA8B9BC);
    return Material(
      color: selected ? const Color(0xFF17363A) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? const Color(0xFF3F8890) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? item.selectedIcon : item.icon,
                size: 20,
                color: iconColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? Colors.white : const Color(0xFFA8B9BC),
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
