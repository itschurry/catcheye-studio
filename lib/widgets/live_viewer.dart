import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Displays an RTSP stream player.
class LiveViewer extends StatelessWidget {
  final VideoController controller;
  final bool connected;
  final BoxFit fit;

  const LiveViewer({
    super.key,
    required this.controller,
    required this.connected,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    if (!connected) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'No stream',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Video(
        controller: controller,
        fit: fit,
        controls: NoVideoControls,
      ),
    );
  }
}
