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
    const brandOrange = Color(0xFFFF7A2F);
    const neutralPrimary = Color(0xFFE2E8F0);
    const appBackground = Color(0xFF151515);
    const appSurface = Color(0xFF252525);
    const appSurfaceHigh = Color(0xFF303030);

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
            primary: neutralPrimary,
            onPrimary: Color(0xFF111111),
            primaryContainer: Color(0xFF4A4A4A),
            onPrimaryContainer: Colors.white,
            secondary: brandOrange,
            onSecondary: Color(0xFF241005),
            surface: appSurface,
            onSurface: Color(0xFFEDEDED),
            surfaceContainerHighest: appSurfaceHigh,
            outline: Color(0xFF686868),
          ),
          dividerColor: const Color(0xFF4A4A4A),
          useMaterial3: true,
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: neutralPrimary,
              foregroundColor: const Color(0xFF111111),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: neutralPrimary,
              side: const BorderSide(color: Color(0xFF666666)),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          navigationRailTheme: const NavigationRailThemeData(
            backgroundColor: appSurface,
            indicatorColor: Color(0xFF333333),
            selectedIconTheme: IconThemeData(color: neutralPrimary),
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
      color: const Color(0xFF252525),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              for (var i = 0; i < items.length; i++) ...[
                _SidebarButton(
                  item: items[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelected(i),
                ),
                const SizedBox(height: 6),
              ],
              const Spacer(),
              Image.asset('assets/logo.png', height: 40, fit: BoxFit.contain),
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
        ? const Color(0xFFE5E7EB)
        : const Color(0xFFA3A3A3);
    return Material(
      color: selected ? const Color(0xFF3A3A3A) : Colors.transparent,
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
              color: selected ? const Color(0xFF737373) : Colors.transparent,
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
