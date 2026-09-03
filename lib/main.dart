import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/roi_config_provider.dart';
import 'providers/reference_credential_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/camera_depth_calibration_screen.dart';
import 'screens/camera_properties_screen.dart';
import 'screens/capture_images_screen.dart';
import 'screens/inspection_results_screen.dart';
import 'screens/monitor_screen.dart';
import 'screens/reference_images_screen.dart';
import 'screens/roi_editor_screen.dart';
import 'screens/viewer_screen.dart';
import 'models/app_settings.dart';
import 'services/frame_receiver_service.dart';
import 'services/remote_reference_api_service.dart';

List<int> visibleAppItemIndexes(
  RemoteDeviceKind? kind,
  bool isPhone, {
  bool referenceManagementAvailable = false,
}) {
  if (isPhone) {
    return switch (kind) {
      RemoteDeviceKind.hss => const [0, 1, 2],
      RemoteDeviceKind.pick => const [0, 2],
      RemoteDeviceKind.capture => const [0, 5, 1],
      RemoteDeviceKind.inspection =>
        referenceManagementAvailable ? const [0, 6, 7] : const [0, 6],
      null => const [0],
    };
  }
  return switch (kind) {
    RemoteDeviceKind.hss => const [0, 1, 2, 3],
    RemoteDeviceKind.pick => const [0, 2, 4],
    RemoteDeviceKind.capture => const [0, 5, 1, 3],
    RemoteDeviceKind.inspection =>
      referenceManagementAvailable ? const [0, 6, 7] : const [0, 6],
    null => const [0],
  };
}

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
        ChangeNotifierProvider(create: (_) => ReferenceCredentialProvider()),
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

enum _ReferenceDiscoveryState { idle, loading, available, unsupported, failed }

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _viewerReconnectToken = 0;
  String? _viewerStreamUrl;
  final RemoteReferenceApiService _referenceApi = RemoteReferenceApiService(
    requestTimeout: const Duration(seconds: 3),
  );
  String? _referenceDiscoveryKey;
  String? _referenceEndpointKey;
  ReferenceApiStatus? _referenceStatus;
  _ReferenceDiscoveryState _referenceDiscoveryState =
      _ReferenceDiscoveryState.idle;
  bool _resultsMounted = false;
  bool _referenceMounted = false;
  static const _wideBreakpoint = 900.0;
  static const _phoneBreakpoint = 600.0;

  static const _items = [
    _NavItem(
      label: 'Viewer',
      icon: Icons.live_tv_outlined,
      selectedIcon: Icons.live_tv,
    ),
    _NavItem(
      label: 'Monitor',
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view,
    ),
    _NavItem(
      label: 'ROI Editor',
      icon: Icons.edit_location_alt_outlined,
      selectedIcon: Icons.edit_location_alt,
    ),
    _NavItem(
      label: 'Camera Properties',
      icon: Icons.settings_input_component_outlined,
      selectedIcon: Icons.settings_input_component,
    ),
    _NavItem(
      label: 'Camera Geometry',
      icon: Icons.threed_rotation_outlined,
      selectedIcon: Icons.threed_rotation,
    ),
    _NavItem(
      label: 'Images',
      icon: Icons.photo_library_outlined,
      selectedIcon: Icons.photo_library,
    ),
    _NavItem(
      label: 'Results',
      icon: Icons.fact_check_outlined,
      selectedIcon: Icons.fact_check,
    ),
    _NavItem(
      label: 'References',
      icon: Icons.collections_bookmark_outlined,
      selectedIcon: Icons.collections_bookmark,
    ),
  ];

  @override
  void dispose() {
    _referenceApi.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final connectionRevision = context
        .watch<SettingsProvider>()
        .connectionRevision;
    final credentialRevision = context
        .watch<ReferenceCredentialProvider>()
        .revision;
    final remoteDeviceKind = settings.remoteDeviceKind;
    _discoverReferenceCapabilities(
      settings,
      credentialRevision,
      connectionRevision,
    );
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= _wideBreakpoint;
    final isPhone = width < _phoneBreakpoint;
    final referenceManagementAvailable =
        remoteDeviceKind == RemoteDeviceKind.inspection &&
        switch (_referenceDiscoveryState) {
          _ReferenceDiscoveryState.available ||
          _ReferenceDiscoveryState.failed => true,
          _ReferenceDiscoveryState.loading =>
            _referenceStatus?.capabilities.hasReferenceManagement == true,
          _ReferenceDiscoveryState.idle ||
          _ReferenceDiscoveryState.unsupported => false,
        };
    final visibleItemIndexes = _visibleItemIndexes(
      remoteDeviceKind,
      isPhone,
      referenceManagementAvailable: referenceManagementAvailable,
    );
    final selectedIndex = visibleItemIndexes.contains(_selectedIndex)
        ? _selectedIndex
        : 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: isWide
            ? Row(
                children: [
                  _AppSidebar(
                    selectedIndex: selectedIndex,
                    items: _items,
                    visibleItemIndexes: visibleItemIndexes,
                    onSelected: (index) => _onNavSelected(index, selectedIndex),
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(
                    child: _buildScreenArea(
                      selectedIndex,
                      isPhone: isPhone,
                      referenceManagementAvailable:
                          referenceManagementAvailable,
                    ),
                  ),
                ],
              )
            : _buildScreenArea(
                selectedIndex,
                isPhone: isPhone,
                referenceManagementAvailable: referenceManagementAvailable,
              ),
      ),
      bottomNavigationBar: isWide
          ? null
          : _BottomNavigation(
              selectedIndex: selectedIndex,
              visibleItemIndexes: visibleItemIndexes,
              items: _items,
              isPhone: isPhone,
              onSelected: (index) => _onNavSelected(index, selectedIndex),
            ),
    );
  }

  Widget _buildScreenArea(
    int selectedIndex, {
    required bool isPhone,
    required bool referenceManagementAvailable,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (selectedIndex != 6 && selectedIndex != 7)
          _screenForIndex(selectedIndex, isPhone: isPhone),
        if (_resultsMounted)
          Offstage(
            offstage: selectedIndex != 6,
            child: TickerMode(
              enabled: selectedIndex == 6,
              child: const InspectionResultsScreen(),
            ),
          ),
        if (_referenceMounted && referenceManagementAvailable)
          Offstage(
            offstage: selectedIndex != 7,
            child: TickerMode(
              enabled: selectedIndex == 7,
              child: ReferenceImagesScreen(
                isPhone: isPhone,
                initialStatus: _referenceStatus,
                refreshKey: _referenceDiscoveryKey,
              ),
            ),
          ),
      ],
    );
  }

  Widget _screenForIndex(int index, {required bool isPhone}) {
    return switch (index) {
      0 => ViewerScreen(
        reconnectToken: _viewerReconnectToken,
        isPhone: isPhone,
        initialStreamUrl: _viewerStreamUrl,
      ),
      1 => MonitorScreen(isPhone: isPhone, onOpenViewer: _openMonitorCamera),
      2 => RoiEditorScreen(isPhone: isPhone),
      3 => const CameraPropertiesScreen(),
      4 => const CameraDepthCalibrationScreen(),
      5 => CaptureImagesScreen(isPhone: isPhone),
      6 => const InspectionResultsScreen(),
      7 => ReferenceImagesScreen(
        isPhone: isPhone,
        initialStatus: _referenceStatus,
        refreshKey: _referenceDiscoveryKey,
      ),
      _ => throw StateError('Unsupported screen index: $index'),
    };
  }

  List<int> _visibleItemIndexes(
    RemoteDeviceKind? kind,
    bool isPhone, {
    required bool referenceManagementAvailable,
  }) {
    return visibleAppItemIndexes(
      kind,
      isPhone,
      referenceManagementAvailable: referenceManagementAvailable,
    );
  }

  void _discoverReferenceCapabilities(
    AppSettings settings,
    int credentialRevision,
    int connectionRevision,
  ) {
    final isInspection =
        settings.remoteDeviceKind == RemoteDeviceKind.inspection;
    final endpointKey = isInspection
        ? '${settings.detectorBaseUrl}|${settings.apiBasePath}'
        : null;
    final key = endpointKey == null
        ? null
        : '$endpointKey|$credentialRevision|$connectionRevision';
    if (_referenceDiscoveryKey == key) return;
    final endpointChanged = _referenceEndpointKey != endpointKey;
    _referenceDiscoveryKey = key;
    _referenceEndpointKey = endpointKey;
    if (endpointChanged) _referenceStatus = null;
    if (key == null) {
      _referenceDiscoveryState = _ReferenceDiscoveryState.idle;
      return;
    }
    _referenceDiscoveryState = _ReferenceDiscoveryState.loading;
    unawaited(_loadReferenceCapabilities(settings, key));
  }

  Future<void> _loadReferenceCapabilities(
    AppSettings settings,
    String discoveryKey,
  ) async {
    try {
      final token = await context.read<ReferenceCredentialProvider>().readToken(
        settings,
      );
      if (token == null || token.isEmpty) {
        if (!mounted || _referenceDiscoveryKey != discoveryKey) return;
        setState(
          () => _referenceDiscoveryState = _ReferenceDiscoveryState.failed,
        );
        return;
      }
      final status = await _referenceApi.fetchStatus(
        settings,
        bearerToken: token,
      );
      if (!mounted || _referenceDiscoveryKey != discoveryKey) return;
      setState(() {
        _referenceStatus = status;
        _referenceDiscoveryState = status.capabilities.hasReferenceManagement
            ? _ReferenceDiscoveryState.available
            : _ReferenceDiscoveryState.unsupported;
      });
    } on RemoteReferenceApiException catch (error) {
      if (!mounted || _referenceDiscoveryKey != discoveryKey) return;
      final statusMissing =
          error.statusCode == 404 &&
          error.uri.path.endsWith('/reference/status');
      setState(() {
        if (statusMissing) _referenceStatus = null;
        _referenceDiscoveryState = statusMissing
            ? _ReferenceDiscoveryState.unsupported
            : _ReferenceDiscoveryState.failed;
      });
    } catch (_) {
      if (!mounted || _referenceDiscoveryKey != discoveryKey) return;
      setState(
        () => _referenceDiscoveryState = _ReferenceDiscoveryState.failed,
      );
    }
  }

  void _openMonitorCamera(String streamUrl) {
    setState(() {
      _viewerStreamUrl = streamUrl;
      _viewerReconnectToken += 1;
      _selectedIndex = 0;
    });
  }

  void _onNavSelected(int index, int currentSelectedIndex) {
    if (index == currentSelectedIndex) {
      return;
    }
    final receiver = context.read<FrameReceiverService>();
    final shouldReconnectViewer =
        (currentSelectedIndex == 0 || currentSelectedIndex == 2) &&
        index != 0 &&
        (receiver.connected || receiver.connecting);
    if (index != 0 && index != 2) {
      _viewerStreamUrl = null;
      if (shouldReconnectViewer) {
        _viewerReconnectToken += 1;
      }
      unawaited(receiver.disconnect());
    }
    setState(() {
      _selectedIndex = index;
      if (index == 6) _resultsMounted = true;
      if (index == 7) _referenceMounted = true;
    });
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
    required this.visibleItemIndexes,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<_NavItem> items;
  final List<int> visibleItemIndexes;
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
              for (final i in visibleItemIndexes) ...[
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

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.selectedIndex,
    required this.visibleItemIndexes,
    required this.items,
    required this.isPhone,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<int> visibleItemIndexes;
  final List<_NavItem> items;
  final bool isPhone;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: const Color(0xFF252525),
      currentIndex: visibleItemIndexes.indexOf(selectedIndex),
      showUnselectedLabels: !isPhone,
      onTap: (selectedNavIndex) {
        onSelected(visibleItemIndexes[selectedNavIndex]);
      },
      items: [
        for (final index in visibleItemIndexes)
          BottomNavigationBarItem(
            icon: Icon(items[index].icon),
            activeIcon: Icon(items[index].selectedIcon),
            label: items[index].label,
          ),
      ],
    );
  }
}
