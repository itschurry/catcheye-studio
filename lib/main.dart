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

  static const _destinations = [
    NavigationRailDestination(
      icon: Icon(Icons.live_tv_outlined),
      selectedIcon: Icon(Icons.live_tv),
      label: Text('Viewer'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.edit_location_alt_outlined),
      selectedIcon: Icon(Icons.edit_location_alt),
      label: Text('ROI Editor'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.grid_on_outlined),
      selectedIcon: Icon(Icons.grid_on),
      label: Text('Camera Calibration'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.threed_rotation_outlined),
      selectedIcon: Icon(Icons.threed_rotation),
      label: Text('Camera-Depth Calibration'),
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
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              if (index >= 2) {
                unawaited(context.read<FrameReceiverService>().disconnect());
              }
              setState(() => _selectedIndex = index);
            },
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F6F5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF73D4DC)),
                    ),
                    child: Image.asset(
                      'assets/emblem.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
            destinations: _destinations,
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _screens[_selectedIndex]),
        ],
      ),
    );
  }
}
