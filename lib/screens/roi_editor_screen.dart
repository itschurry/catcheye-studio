import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../models/roi_config.dart';
import '../providers/roi_config_provider.dart';
import '../providers/settings_provider.dart';
import '../services/frame_receiver_service.dart';
import '../services/remote_hss_api_service.dart';
import '../widgets/roi_editor_canvas.dart';
import '../widgets/zone_list_panel.dart';

/// ROI Editor screen

class RoiEditorScreen extends StatefulWidget {
  const RoiEditorScreen({super.key, this.isPhone = false});

  final bool isPhone;

  @override
  State<RoiEditorScreen> createState() => _RoiEditorScreenState();
}

class _RoiEditorScreenState extends State<RoiEditorScreen> {
  FrameReceiverService? _receiver;
  bool _zonePanelExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final receiver = context.read<FrameReceiverService>();
      _receiver = receiver;
      receiver.addListener(_onFrameChanged);
      _onFrameChanged();
      final uri = context.read<SettingsProvider>().settings.streamUri;
      if (uri.scheme == 'ws' || uri.scheme == 'wss') {
        unawaited(receiver.connect(uri.toString()));
      }
    });
  }

  void _onFrameChanged() {
    if (!mounted) return;
    final size = _cameraFrame(_receiver!)?.size;
    if (size != null) {
      context.read<RoiConfigProvider>().syncImageSize(
        size.width.round(),
        size.height.round(),
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    _receiver?.removeListener(_onFrameChanged);
    super.dispose();
  }

  String get _streamStatus {
    final uri = context.read<SettingsProvider>().settings.streamUri;
    if (uri.scheme != 'ws' && uri.scheme != 'wss') return 'WebSocket required';
    final receiver = _receiver;
    if (receiver == null || receiver.connecting) return 'Connecting';
    if (receiver.errorMessage != null) return receiver.errorMessage!;
    if (!receiver.connected) return 'Disconnected';
    return _cameraFrame(receiver) == null ? 'Waiting for camera' : 'Live';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<RoiConfigProvider, SettingsProvider>(
      builder: (context, provider, settingsProvider, _) {
        final allowedKinds = _allowedKinds(
          settingsProvider.settings.remoteDeviceKind,
        );
        if (!allowedKinds.contains(provider.selectedKind)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              provider.selectKind(allowedKinds.first);
            }
          });
        }
        return Column(
          children: [
            // Toolbar
            _buildToolbar(
              context,
              provider,
              allowedKinds,
              isPhone: widget.isPhone,
            ),
            const Divider(height: 1),

            // Main area
            Expanded(
              child: widget.isPhone
                  ? Column(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              _buildConfigInfoBar(provider),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: RoiEditorCanvas(
                                    backgroundImageBytes: _receiver == null
                                        ? null
                                        : _cameraFrame(_receiver!)?.jpegBytes,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const Text(
                                'Zones',
                                style: TextStyle(fontSize: 14),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () => setState(
                                  () =>
                                      _zonePanelExpanded = !_zonePanelExpanded,
                                ),
                                icon: Icon(
                                  _zonePanelExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                ),
                                label: Text(
                                  _zonePanelExpanded
                                      ? 'Hide zones'
                                      : 'Show zones',
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_zonePanelExpanded)
                          Expanded(child: const ZoneListPanel()),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              _buildConfigInfoBar(provider),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: RoiEditorCanvas(
                                    backgroundImageBytes: _receiver == null
                                        ? null
                                        : _cameraFrame(_receiver!)?.jpegBytes,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 280,
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                          ),
                          child: const ZoneListPanel(),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  ViewerStreamFrame? _cameraFrame(FrameReceiverService receiver) {
    for (final frame in receiver.streams.values) {
      if (frame.isJpeg && _isCameraFrame(frame)) {
        return frame;
      }
    }
    return null;
  }

  bool _isCameraFrame(ViewerStreamFrame frame) {
    return [frame.key, frame.name, frame.kind]
        .map((v) => v.toLowerCase())
        .any(
          (value) =>
              value == 'camera' ||
              value == 'color' ||
              value == 'rgb' ||
              value == 'rgb_camera' ||
              value.contains('color') ||
              value.contains('rgb'),
        );
  }

  Widget _buildToolbar(
    BuildContext context,
    RoiConfigProvider provider,
    List<RoiConfigKind> allowedKinds, {
    required bool isPhone,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surface,
      child: Row(
        children: [
          Icon(Icons.edit_location_alt, size: 20, color: colorScheme.secondary),
          const SizedBox(width: 8),
          const Text(
            'ROI Editor',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 16),
          SegmentedButton<RoiConfigKind>(
            segments: [
              if (allowedKinds.contains(RoiConfigKind.person))
                const ButtonSegment(
                  value: RoiConfigKind.person,
                  label: Text('Person ROI'),
                  icon: Icon(Icons.person_outline),
                ),
              if (allowedKinds.contains(RoiConfigKind.pallet))
                const ButtonSegment(
                  value: RoiConfigKind.pallet,
                  label: Text('Pallet ROI'),
                  icon: Icon(Icons.inventory_2_outlined),
                ),
            ],
            selected: {
              allowedKinds.contains(provider.selectedKind)
                  ? provider.selectedKind
                  : allowedKinds.first,
            },
            onSelectionChanged: (selection) {
              provider.selectKind(selection.first);
            },
          ),
          const SizedBox(width: 16),

          if (!isPhone)
            if (provider.filePath != null)
              Expanded(
                child: Text(
                  provider.filePath!,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              const Expanded(
                child: Text(
                  'No file',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),

          if (provider.isDirty)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade800,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Modified',
                style: TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),

          // Action buttons
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined, size: 20),
            tooltip: 'Load ${provider.selectedKind.label} From Device',
            onPressed: () => _loadFromDevice(context, provider),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined, size: 20),
            tooltip: 'Push ${provider.selectedKind.label} To Device',
            onPressed: () => _pushToDevice(context, provider),
          ),
        ],
      ),
    );
  }

  List<RoiConfigKind> _allowedKinds(RemoteDeviceKind? deviceKind) {
    return switch (deviceKind) {
      RemoteDeviceKind.hss => const [
        RoiConfigKind.person,
        RoiConfigKind.pallet,
      ],
      RemoteDeviceKind.pick => const [RoiConfigKind.pallet],
      RemoteDeviceKind.capture => const [RoiConfigKind.person],
      RemoteDeviceKind.inspection => const [RoiConfigKind.person],
      null => const [RoiConfigKind.person],
    };
  }

  Widget _buildConfigInfoBar(RoiConfigProvider provider) {
    return Builder(
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            _InfoChip(
              label: 'Camera',
              value: provider.config.cameraId.isEmpty
                  ? 'N/A'
                  : provider.config.cameraId,
            ),
            const SizedBox(width: 16),
            _InfoChip(
              label: 'Resolution',
              value:
                  '${provider.config.imageWidth} × ${provider.config.imageHeight}',
            ),
            const SizedBox(width: 16),
            _InfoChip(
              label: 'Zones',
              value: '${provider.config.allowedZones.length}',
            ),
            const SizedBox(width: 16),
            _InfoChip(label: 'Stream', value: _streamStatus),
            const Spacer(),
            if (provider.errorMessage != null)
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 14, color: Colors.red),
                  const SizedBox(width: 4),
                  Text(
                    provider.errorMessage!,
                    style: const TextStyle(fontSize: 11, color: Colors.red),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadFromDevice(
    BuildContext context,
    RoiConfigProvider provider,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final api = RemoteHssApiService();
    final kind = provider.selectedKind;

    try {
      final config = await api.fetchRoi(settings, kind: kind);
      provider.loadFromConfig(
        config,
        sourceLabel: settings.buildApiUri(kind.endpoint).toString(),
        kind: kind,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${kind.label} loaded from device')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load ${kind.label}: $e')),
        );
      }
    }
  }

  Future<void> _pushToDevice(
    BuildContext context,
    RoiConfigProvider provider,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final api = RemoteHssApiService();
    final kind = provider.selectedKind;

    try {
      await api.pushRoi(settings, provider.config, kind: kind);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${kind.label} pushed to device')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to push ${kind.label}: $e')),
        );
      }
    }
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
