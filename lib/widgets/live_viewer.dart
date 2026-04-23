import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Displays either an RTSP player or WebSocket JPEG frames.
class LiveViewer extends StatelessWidget {
  final VideoController controller;
  final bool connected;
  final bool isRtsp;
  final Uint8List? frameData;
  final BoxFit fit;

  const LiveViewer({
    super.key,
    required this.controller,
    required this.connected,
    required this.isRtsp,
    this.frameData,
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
              Text('No stream', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: isRtsp
          ? Video(controller: controller, fit: fit, controls: NoVideoControls)
          : frameData == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Image.memory(
                frameData!,
                fit: fit,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
            ),
    );
  }
}
