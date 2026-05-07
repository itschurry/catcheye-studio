import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/roi_config.dart';
import '../providers/roi_config_provider.dart';
import '../providers/settings_provider.dart';
import '../services/remote_guard_api_service.dart';
import '../widgets/roi_editor_canvas.dart';
import '../widgets/zone_list_panel.dart';

/// ROI Editor screen

class RoiEditorScreen extends StatelessWidget {
  const RoiEditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RoiConfigProvider>(
      builder: (context, provider, _) {
        return Column(
          children: [
            // Toolbar
            _buildToolbar(context, provider),
            const Divider(height: 1),

            // Main area
            Expanded(
              child: Row(
                children: [
                  // Canvas
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        // Config info bar
                        _buildConfigInfoBar(provider),
                        // ROI canvas
                        const Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: RoiEditorCanvas(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Zone list panel
                  Container(
                    width: 280,
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Theme.of(context).dividerColor),
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

  Widget _buildToolbar(BuildContext context, RoiConfigProvider provider) {
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
            segments: const [
              ButtonSegment(
                value: RoiConfigKind.person,
                label: Text('Person ROI'),
                icon: Icon(Icons.person_outline),
              ),
              ButtonSegment(
                value: RoiConfigKind.pallet,
                label: Text('Pallet ROI'),
                icon: Icon(Icons.inventory_2_outlined),
              ),
            ],
            selected: {provider.selectedKind},
            onSelectionChanged: (selection) {
              provider.selectKind(selection.first);
            },
          ),
          const SizedBox(width: 16),

          // File path
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
    final api = RemoteGuardApiService();
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
    final api = RemoteGuardApiService();
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
