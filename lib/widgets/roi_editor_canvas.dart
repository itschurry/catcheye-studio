import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/roi_config.dart';
import '../providers/roi_config_provider.dart';
import '../services/frame_receiver_service.dart';
import 'roi_canvas_painter.dart';

/// Canvas widget for visually editing ROI polygons

class RoiEditorCanvas extends StatefulWidget {
  const RoiEditorCanvas({super.key, this.backgroundImageBytes});

  final Uint8List? backgroundImageBytes;

  @override
  State<RoiEditorCanvas> createState() => _RoiEditorCanvasState();
}

class _RoiEditorCanvasState extends State<RoiEditorCanvas> {
  int? _draggingZone;
  int? _draggingPoint;
  int? _hoveredZone;
  int? _hoveredPoint;
  FrameReceiverService? _frameReceiver;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final receiver = context.read<FrameReceiverService>();
    if (_frameReceiver != receiver) {
      _frameReceiver?.removeListener(_syncFrameSize);
      _frameReceiver = receiver;
      _frameReceiver!.addListener(_syncFrameSize);
    }
  }

  void _syncFrameSize() {
    final size = _frameReceiver?.frameSize;
    if (size == null) return;
    context.read<RoiConfigProvider>().syncImageSize(
      size.width.round(),
      size.height.round(),
    );
  }

  @override
  void dispose() {
    _frameReceiver?.removeListener(_syncFrameSize);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RoiConfigProvider>(
      builder: (context, provider, _) {
        final config = provider.config;

        return LayoutBuilder(
          builder: (context, constraints) {
            final aspect = config.imageWidth > 0 && config.imageHeight > 0
                ? config.imageWidth / config.imageHeight
                : 16 / 9;

            double canvasWidth = constraints.maxWidth;
            double canvasHeight = canvasWidth / aspect;
            if (canvasHeight > constraints.maxHeight) {
              canvasHeight = constraints.maxHeight;
              canvasWidth = canvasHeight * aspect;
            }

            final canvasSize = Size(canvasWidth, canvasHeight);
            final scaleX = config.imageWidth > 0
                ? canvasWidth / config.imageWidth
                : 1.0;
            final scaleY = config.imageHeight > 0
                ? canvasHeight / config.imageHeight
                : 1.0;

            return Center(
              child: Container(
                width: canvasWidth,
                height: canvasHeight,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  border: Border.all(color: Colors.grey.shade700),
                  borderRadius: BorderRadius.circular(4),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.backgroundImageBytes != null)
                      Image.memory(
                        widget.backgroundImageBytes!,
                        fit: BoxFit.fill,
                      ),
                    MouseRegion(
                      onHover: (event) =>
                          _onHover(event.localPosition, config, scaleX, scaleY),
                      onExit: (_) => setState(() {
                        _hoveredZone = null;
                        _hoveredPoint = null;
                      }),
                      cursor: _hoveredPoint != null
                          ? SystemMouseCursors.grab
                          : SystemMouseCursors.precise,
                      child: GestureDetector(
                        onPanStart: (details) => _onPanStart(
                          details.localPosition,
                          config,
                          scaleX,
                          scaleY,
                        ),
                        onPanUpdate: (details) => _onPanUpdate(
                          details.localPosition,
                          provider,
                          scaleX,
                          scaleY,
                        ),
                        onPanEnd: (_) => _onPanEnd(),
                        onTapUp: (details) => _onTapUp(
                          details.localPosition,
                          provider,
                          config,
                          scaleX,
                          scaleY,
                        ),
                        child: CustomPaint(
                          size: canvasSize,
                          painter: RoiCanvasPainter(
                            config: config,
                            selectedZoneIndex: provider.selectedZoneIndex,
                            hoveredPointZone: _hoveredZone,
                            hoveredPointIndex: _hoveredPoint,
                            canvasSize: canvasSize,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _onHover(Offset pos, CameraRoiConfig config, double sx, double sy) {
    int? foundZone;
    int? foundPoint;
    const hitRadius = 10.0;

    for (var i = 0; i < config.allowedZones.length; i++) {
      final zone = config.allowedZones[i];
      for (var j = 0; j < zone.points.length; j++) {
        final p = zone.points[j];
        final canvasPos = Offset(p.x * sx, p.y * sy);
        if ((pos - canvasPos).distance < hitRadius) {
          foundZone = i;
          foundPoint = j;
          break;
        }
      }
      if (foundZone != null) break;
    }

    if (foundZone != _hoveredZone || foundPoint != _hoveredPoint) {
      setState(() {
        _hoveredZone = foundZone;
        _hoveredPoint = foundPoint;
      });
    }
  }

  void _onPanStart(Offset pos, CameraRoiConfig config, double sx, double sy) {
    const hitRadius = 10.0;
    for (var i = 0; i < config.allowedZones.length; i++) {
      final zone = config.allowedZones[i];
      for (var j = 0; j < zone.points.length; j++) {
        final p = zone.points[j];
        final canvasPos = Offset(p.x * sx, p.y * sy);
        if ((pos - canvasPos).distance < hitRadius) {
          _draggingZone = i;
          _draggingPoint = j;
          return;
        }
      }
    }
  }

  void _onPanUpdate(
    Offset pos,
    RoiConfigProvider provider,
    double sx,
    double sy,
  ) {
    if (_draggingZone == null || _draggingPoint == null) return;

    final config = provider.config;
    final newX = (pos.dx / sx).clamp(0.0, config.imageWidth.toDouble());
    final newY = (pos.dy / sy).clamp(0.0, config.imageHeight.toDouble());

    provider.updatePoint(_draggingZone!, _draggingPoint!, newX, newY);
  }

  void _onPanEnd() {
    _draggingZone = null;
    _draggingPoint = null;
  }

  void _onTapUp(
    Offset pos,
    RoiConfigProvider provider,
    CameraRoiConfig config,
    double sx,
    double sy,
  ) {
    // Tap on a point to select its zone
    const hitRadius = 10.0;
    for (var i = 0; i < config.allowedZones.length; i++) {
      final zone = config.allowedZones[i];
      for (var j = 0; j < zone.points.length; j++) {
        final p = zone.points[j];
        final canvasPos = Offset(p.x * sx, p.y * sy);
        if ((pos - canvasPos).distance < hitRadius) {
          provider.selectZone(i);
          return;
        }
      }
    }
  }
}
