import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/roi_config.dart';
import '../providers/roi_config_provider.dart';

/// Zone list and editing side panel

class ZoneListPanel extends StatelessWidget {
  const ZoneListPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RoiConfigProvider>(
      builder: (context, provider, _) {
        final config = provider.config;
        final zones = config.allowedZones;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.layers, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Allowed Zones',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    tooltip: 'Add Zone',
                    onPressed: provider.addZone,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Zone list
            Expanded(
              child: zones.isEmpty
                  ? const Center(
                      child: Text(
                        'No zones.\nClick + to add a zone.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: zones.length,
                      itemBuilder: (context, index) {
                        final zone = zones[index];
                        final isSelected = index == provider.selectedZoneIndex;

                        return Container(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primaryContainer
                                    .withValues(alpha: 0.3)
                              : null,
                          child: ListTile(
                            dense: true,
                            selected: isSelected,
                            leading: Icon(
                              zone.enabled
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              size: 18,
                              color: zone.enabled
                                  ? Colors.cyanAccent
                                  : Colors.grey,
                            ),
                            title: Text(
                              zone.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              '${zone.points.length} points · ${zone.id}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: PopupMenuButton<String>(
                              iconSize: 18,
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'toggle',
                                  child: Text('Toggle Enable'),
                                ),
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Rename'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                              onSelected: (action) => _onZoneAction(
                                context,
                                provider,
                                index,
                                action,
                              ),
                            ),
                            onTap: () => provider.selectZone(index),
                          ),
                        );
                      },
                    ),
            ),

            // Selected zone info
            if (provider.selectedZone != null) ...[
              const Divider(height: 1),
              _buildSelectedZoneInfo(context, provider),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSelectedZoneInfo(
    BuildContext context,
    RoiConfigProvider provider,
  ) {
    final zone = provider.selectedZone!;
    final config = provider.config;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selected: ${zone.name}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Points: ${zone.points.length}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text(
                    'Add Point',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () {
                    final newPoint = _computeNewPoint(zone, config);
                    provider.addPoint(provider.selectedZoneIndex, newPoint);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: zone.points.length,
              itemBuilder: (context, pointIndex) {
                final point = zone.points[pointIndex];
                final canRemove = zone.points.length > 3;
                return _PointRow(
                  index: pointIndex,
                  point: point,
                  canRemove: canRemove,
                  onRemove: canRemove
                      ? () => provider.removePoint(
                          provider.selectedZoneIndex,
                          pointIndex,
                        )
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _onZoneAction(
    BuildContext context,
    RoiConfigProvider provider,
    int index,
    String action,
  ) {
    switch (action) {
      case 'toggle':
        provider.toggleZoneEnabled(index);
        break;
      case 'rename':
        _showRenameDialog(context, provider, index);
        break;
      case 'delete':
        provider.removeZone(index);
        break;
    }
  }

  void _showRenameDialog(
    BuildContext context,
    RoiConfigProvider provider,
    int index,
  ) {
    final controller = TextEditingController(
      text: provider.config.allowedZones[index].name,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Zone'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Zone Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              provider.updateZone(index, name: controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  RoiPoint _computeNewPoint(RoiPolygon zone, CameraRoiConfig config) {
    if (zone.points.isNotEmpty) {
      final last = zone.points.last;
      final first = zone.points.first;
      return RoiPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2);
    }
    return RoiPoint(x: config.imageWidth / 2.0, y: config.imageHeight / 2.0);
  }
}

class _PointRow extends StatelessWidget {
  final int index;
  final RoiPoint point;
  final bool canRemove;
  final VoidCallback? onRemove;

  const _PointRow({
    required this.index,
    required this.point,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${index + 1}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              'x ${point.x.toStringAsFixed(0)}, y ${point.y.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            tooltip: canRemove ? 'Delete Point' : 'Polygon needs 3 points',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            color: canRemove ? Colors.redAccent : Colors.grey,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
