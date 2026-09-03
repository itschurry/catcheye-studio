import 'package:flutter/material.dart';

import '../services/remote_capture_api_service.dart';

class StationCaptureActions extends StatelessWidget {
  const StationCaptureActions({
    super.key,
    required this.status,
    required this.connected,
    required this.inFlight,
    required this.onCapture,
  });

  final StationCaptureStatus? status;
  final bool connected;
  final bool inFlight;
  final ValueChanged<StationCaptureTarget> onCapture;

  @override
  Widget build(BuildContext context) {
    final current = status;
    if (current == null) return const SizedBox.shrink();
    final enabled =
        connected &&
        !inFlight &&
        current.ready &&
        current.pendingCount < current.maxPendingCaptures;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final target in current.captureTargets)
          FilledButton.icon(
            key: ValueKey('station-capture-${target.path}'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            icon: const Icon(Icons.camera_alt_outlined, size: 16),
            label: Text(
              target == StationCaptureTarget.all
                  ? '${target.label} (${current.cameras.length})'
                  : target.label,
            ),
            onPressed: enabled ? () => onCapture(target) : null,
          ),
      ],
    );
  }
}
