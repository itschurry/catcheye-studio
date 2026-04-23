import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/frame_receiver_service.dart';
import '../widgets/live_viewer.dart';

/// Live preview viewer screen — connects to the remote detector RTSP or WebSocket stream.

class ViewerScreen extends StatelessWidget {
  const ViewerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<FrameReceiverService, SettingsProvider>(
      builder: (context, receiver, settingsProvider, _) {
        final settings = settingsProvider.settings;
        return Column(
          children: [
            // Toolbar
            _buildToolbar(context, receiver, settings.streamUri.toString()),
            const Divider(height: 1),

            // Frame viewer
            Expanded(
              child: LiveViewer(
                controller: receiver.videoController,
                connected: receiver.connected,
                isRtsp: receiver.isRtsp,
                frameData: receiver.currentFrame,
              ),
            ),

            // Status bar
            _buildStatusBar(receiver, settings.streamUri.toString()),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    FrameReceiverService receiver,
    String defaultStreamUrl,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.live_tv, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Live Viewer',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 24),

          // Connection controls
          if (!receiver.connected && !receiver.connecting) ...[
            FilledButton.icon(
              icon: const Icon(Icons.power, size: 16),
              label: const Text('Connect'),
              onPressed: () => receiver.connect(defaultStreamUrl),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Change URL'),
              onPressed: () =>
                  _showConnectDialog(context, receiver, defaultStreamUrl),
            ),
          ] else if (receiver.connecting) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            const Text('Connecting...', style: TextStyle(fontSize: 13)),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.green),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: Colors.green),
                  SizedBox(width: 6),
                  Text(
                    'Connected',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.power_off, size: 16),
              label: const Text('Disconnect'),
              onPressed: () => receiver.disconnect(),
            ),
          ],

          const Spacer(),

          // Error message
          if (receiver.errorMessage != null)
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 14, color: Colors.red),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      receiver.errorMessage!,
                      style: const TextStyle(fontSize: 11, color: Colors.red),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(
    FrameReceiverService receiver,
    String defaultStreamUrl,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.black26,
      child: Row(
        children: [
          _StatusChip(
            label: 'Status',
            value: receiver.connected
                ? 'Connected'
                : receiver.connecting
                ? 'Connecting'
                : 'Disconnected',
            color: receiver.connected ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 16),
          _StatusChip(
            label: 'FPS',
            value: receiver.isWebSocket ? '${receiver.fps}' : 'N/A (RTSP)',
            color: receiver.isWebSocket
                ? receiver.fps > 20
                      ? Colors.green
                      : receiver.fps > 10
                      ? Colors.orange
                      : Colors.red
                : Colors.grey,
          ),
          const SizedBox(width: 16),
          _StatusChip(
            label: 'Frames',
            value: receiver.isWebSocket
                ? '${receiver.frameCount}'
                : 'N/A (RTSP)',
            color: receiver.isWebSocket ? Colors.cyan : Colors.grey,
          ),
          const SizedBox(width: 16),
          _StatusChip(
            label: 'Transport',
            value: receiver.isWebSocket
                ? 'WebSocket'
                : receiver.isRtsp
                ? 'RTSP'
                : 'Idle',
            color: receiver.connected ? Colors.blueAccent : Colors.grey,
          ),
          const Spacer(),
          Text(
            receiver.connectedUri?.toString() ?? defaultStreamUrl,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _showConnectDialog(
    BuildContext context,
    FrameReceiverService receiver,
    String defaultStreamUrl,
  ) {
    final controller = TextEditingController(text: defaultStreamUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect to Stream'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'RTSP or WebSocket URL',
            hintText:
                'rtsp://192.168.0.10:8554/live 또는 ws://192.168.0.10:8080/',
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              receiver.connect(controller.text.trim());
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.value,
    required this.color,
  });

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
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
