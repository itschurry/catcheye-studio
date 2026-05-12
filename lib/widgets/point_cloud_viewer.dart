import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/frame_receiver_service.dart';

enum PointCloudPalette { depth, x, y, grayscale }

class PointCloudViewport {
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final double minZ;
  final double maxZ;

  const PointCloudViewport({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.minZ,
    required this.maxZ,
  });

  static PointCloudViewport? fromData(
    PointCloudData data, {
    required double minDepth,
    required double maxDepth,
    double paddingRatio = 0.08,
  }) {
    final depthLow = math.min(minDepth, maxDepth);
    final depthHigh = math.max(minDepth, maxDepth);
    double? minX;
    double? maxX;
    double? minY;
    double? maxY;
    double? minZ;
    double? maxZ;

    for (var i = 0; i < data.pointCount; i++) {
      final z = data.zAt(i);
      if (z < depthLow || z > depthHigh) continue;

      final x = data.xAt(i);
      final y = data.yAt(i);
      minX = minX == null ? x : math.min(minX, x);
      maxX = maxX == null ? x : math.max(maxX, x);
      minY = minY == null ? y : math.min(minY, y);
      maxY = maxY == null ? y : math.max(maxY, y);
      minZ = minZ == null ? z : math.min(minZ, z);
      maxZ = maxZ == null ? z : math.max(maxZ, z);
    }

    if (minX == null ||
        maxX == null ||
        minY == null ||
        maxY == null ||
        minZ == null ||
        maxZ == null) {
      return null;
    }

    final rangeX = math.max(maxX - minX, 1.0);
    final rangeY = math.max(maxY - minY, 1.0);
    final rangeZ = math.max(maxZ - minZ, 1.0);
    final padX = rangeX * paddingRatio;
    final padY = rangeY * paddingRatio;
    final padZ = rangeZ * paddingRatio;

    return PointCloudViewport(
      minX: minX - padX,
      maxX: maxX + padX,
      minY: minY - padY,
      maxY: maxY + padY,
      minZ: minZ - padZ,
      maxZ: maxZ + padZ,
    );
  }
}

class PointCloudViewer extends StatefulWidget {
  final PointCloudData data;
  final double pointSize;
  final bool showAxis;
  final double axisScale;
  final double minDepth;
  final double maxDepth;
  final PointCloudViewport? viewport;
  final double yaw;
  final double pitch;
  final double zoom;
  final Offset panOffset;
  final PointCloudPalette palette;
  final List<DetectionPosition> detectionPositions;
  final void Function(double yaw, double pitch)? onViewChanged;
  final ValueChanged<double>? onZoomChanged;
  final ValueChanged<Offset>? onPanChanged;

  const PointCloudViewer({
    super.key,
    required this.data,
    required this.pointSize,
    required this.showAxis,
    required this.axisScale,
    required this.minDepth,
    required this.maxDepth,
    this.viewport,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.panOffset,
    required this.palette,
    this.detectionPositions = const [],
    this.onViewChanged,
    this.onZoomChanged,
    this.onPanChanged,
  });

  @override
  State<PointCloudViewer> createState() => _PointCloudViewerState();
}

class _PointCloudViewerState extends State<PointCloudViewer> {
  double _scaleStartZoom = 1.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) {
          return;
        }
        final delta = event.scrollDelta.dy < 0 ? 1.08 : 0.92;
        widget.onZoomChanged?.call((widget.zoom * delta).clamp(0.2, 8.0));
      },
      onPointerMove: (event) {
        if ((event.buttons & kPrimaryMouseButton) != 0) {
          widget.onViewChanged?.call(
            widget.yaw + event.delta.dx * 0.01,
            widget.pitch + event.delta.dy * 0.01,
          );
          return;
        }
        if ((event.buttons & kSecondaryMouseButton) != 0 ||
            (event.buttons & kMiddleMouseButton) != 0) {
          widget.onPanChanged?.call(widget.panOffset + event.delta);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (_) => _scaleStartZoom = widget.zoom,
        onScaleUpdate: (details) {
          if (details.pointerCount > 1) {
            widget.onZoomChanged?.call(
              (_scaleStartZoom * details.scale).clamp(0.2, 8.0),
            );
            return;
          }
        },
        child: Container(
          color: Colors.black,
          child: ClipRect(
            child: CustomPaint(
              painter: _PointCloudPainter(
                data: widget.data,
                pointSize: widget.pointSize,
                showAxis: widget.showAxis,
                axisScale: widget.axisScale,
                minDepth: widget.minDepth,
                maxDepth: widget.maxDepth,
                viewport: widget.viewport,
                yaw: widget.yaw,
                pitch: widget.pitch,
                zoom: widget.zoom,
                panOffset: widget.panOffset,
                palette: widget.palette,
                detectionPositions: widget.detectionPositions,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectedPoint {
  final Offset offset;
  final double cameraZ;
  final double sourceZ;
  final double colorValue;

  const _ProjectedPoint({
    required this.offset,
    required this.cameraZ,
    required this.sourceZ,
    required this.colorValue,
  });
}

class _ColorRange {
  final double min;
  final double max;

  const _ColorRange(this.min, this.max);
}

class _PointCloudPainter extends CustomPainter {
  final PointCloudData data;
  final double pointSize;
  final bool showAxis;
  final double axisScale;
  final double minDepth;
  final double maxDepth;
  final PointCloudViewport? viewport;
  final double yaw;
  final double pitch;
  final double zoom;
  final Offset panOffset;
  final PointCloudPalette palette;
  final List<DetectionPosition> detectionPositions;

  const _PointCloudPainter({
    required this.data,
    required this.pointSize,
    required this.showAxis,
    required this.axisScale,
    required this.minDepth,
    required this.maxDepth,
    this.viewport,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.panOffset,
    required this.palette,
    required this.detectionPositions,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);

    final depthLow = math.min(minDepth, maxDepth);
    final depthHigh = math.max(minDepth, maxDepth);

    final activeViewport =
        viewport ??
        PointCloudViewport.fromData(
          data,
          minDepth: depthLow,
          maxDepth: depthHigh,
        );
    if (activeViewport == null) {
      _drawEmpty(canvas, size);
      return;
    }

    final rangeX = math.max(activeViewport.maxX - activeViewport.minX, 1.0);
    final rangeY = math.max(activeViewport.maxY - activeViewport.minY, 1.0);
    final rangeZ = math.max(activeViewport.maxZ - activeViewport.minZ, 1.0);
    final sceneRange = math.max(rangeX, math.max(rangeY, rangeZ));
    final scale = math.min(size.width, size.height) / sceneRange * 0.82 * zoom;
    final centerX = (activeViewport.minX + activeViewport.maxX) * 0.5;
    final centerY = (activeViewport.minY + activeViewport.maxY) * 0.5;
    final centerZ = (activeViewport.minZ + activeViewport.maxZ) * 0.5;
    final center = Offset(size.width * 0.5, size.height * 0.5) + panOffset;

    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final cosPitch = math.cos(pitch);
    final sinPitch = math.sin(pitch);

    ({Offset offset, double cameraZ}) project(double x, double y, double z) {
      final tx = x - centerX;
      final ty = y - centerY;
      final tz = z - centerZ;

      final yawX = tx * cosYaw + tz * sinYaw;
      final yawZ = -tx * sinYaw + tz * cosYaw;
      final pitchY = ty * cosPitch - yawZ * sinPitch;
      final pitchZ = ty * sinPitch + yawZ * cosPitch;

      return (
        offset: Offset(center.dx + yawX * scale, center.dy - pitchY * scale),
        cameraZ: pitchZ,
      );
    }

    if (showAxis) {
      _drawAxis(canvas, project);
    }

    final colorRange = _colorRange(data, depthLow, depthHigh, palette);
    final paint = Paint()..style = PaintingStyle.fill;
    final radius = math.max(pointSize, 0.5);
    final projectedPoints = <_ProjectedPoint>[];
    for (var i = 0; i < data.pointCount; i++) {
      final z = data.zAt(i);
      if (z < depthLow || z > depthHigh) continue;
      final projected = project(data.xAt(i), data.yAt(i), z);
      projectedPoints.add(
        _ProjectedPoint(
          offset: projected.offset,
          cameraZ: projected.cameraZ,
          sourceZ: z,
          colorValue: _colorValue(data, i, palette),
        ),
      );
    }

    projectedPoints.sort((a, b) => a.cameraZ.compareTo(b.cameraZ));
    for (final point in projectedPoints) {
      paint.color = _paletteColor(point.colorValue, colorRange, palette);
      canvas.drawCircle(point.offset, radius, paint);
    }

    _drawDetectionPositions(canvas, project, depthLow, depthHigh);
    _drawColorbar(canvas, size, colorRange, palette);
  }

  void _drawDetectionPositions(
    Canvas canvas,
    ({Offset offset, double cameraZ}) Function(double x, double y, double z)
    project,
    double depthLow,
    double depthHigh,
  ) {
    if (detectionPositions.isEmpty) return;

    final markerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFFFFEA00);
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0x55FFEA00);

    for (final detection in detectionPositions) {
      if (detection.z < depthLow || detection.z > depthHigh) continue;

      final projected = project(detection.x, detection.y, detection.z).offset;
      const markerSize = 9.0;
      canvas.drawCircle(projected, markerSize, fillPaint);
      canvas.drawCircle(projected, markerSize, markerPaint);
      canvas.drawLine(
        Offset(projected.dx - markerSize - 4, projected.dy),
        Offset(projected.dx + markerSize + 4, projected.dy),
        markerPaint,
      );
      canvas.drawLine(
        Offset(projected.dx, projected.dy - markerSize - 4),
        Offset(projected.dx, projected.dy + markerSize + 4),
        markerPaint,
      );
      _drawDetectionLabel(canvas, projected, detection);
    }
  }

  void _drawDetectionLabel(
    Canvas canvas,
    Offset marker,
    DetectionPosition detection,
  ) {
    final text =
        '${detection.className} '
        'x:${detection.x.toStringAsFixed(1)} '
        'y:${detection.y.toStringAsFixed(1)} '
        'z:${detection.z.toStringAsFixed(1)}';
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFFFFEA00),
          fontSize: 11,
          fontFamily: 'monospace',
          shadows: [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 260);
    painter.paint(canvas, marker + const Offset(12, -18));
  }

  _ColorRange _colorRange(
    PointCloudData data,
    double depthLow,
    double depthHigh,
    PointCloudPalette palette,
  ) {
    if (palette == PointCloudPalette.depth ||
        palette == PointCloudPalette.grayscale) {
      return _ColorRange(depthLow, depthHigh);
    }

    double? minValue;
    double? maxValue;
    for (var i = 0; i < data.pointCount; i++) {
      final z = data.zAt(i);
      if (z < depthLow || z > depthHigh) continue;
      final value = _colorValue(data, i, palette);
      minValue = minValue == null ? value : math.min(minValue, value);
      maxValue = maxValue == null ? value : math.max(maxValue, value);
    }
    return _ColorRange(minValue ?? 0, maxValue ?? 1);
  }

  double _colorValue(
    PointCloudData data,
    int index,
    PointCloudPalette palette,
  ) {
    return switch (palette) {
      PointCloudPalette.x => data.xAt(index),
      PointCloudPalette.y => data.yAt(index),
      PointCloudPalette.depth || PointCloudPalette.grayscale => data.zAt(index),
    };
  }

  Color _paletteColor(
    double value,
    _ColorRange range,
    PointCloudPalette palette,
  ) {
    final span = math.max(range.max - range.min, 1e-6);
    final t = ((value - range.min) / span).clamp(0.0, 1.0);
    if (palette == PointCloudPalette.grayscale) {
      final level = (t * 255).round().clamp(0, 255);
      return Color.fromARGB(255, level, level, level);
    }
    return _depthColor(t);
  }

  Color _depthColor(double t) {
    if (t < 0.5) {
      return Color.lerp(
        const Color(0xFF4FC3F7),
        const Color(0xFF69F0AE),
        t * 2.0,
      )!;
    }
    return Color.lerp(
      const Color(0xFF69F0AE),
      const Color(0xFFFF7043),
      (t - 0.5) * 2.0,
    )!;
  }

  void _drawColorbar(
    Canvas canvas,
    Size size,
    _ColorRange range,
    PointCloudPalette palette,
  ) {
    const barWidth = 14.0;
    const barHeight = 140.0;
    const right = 16.0;
    const top = 16.0;
    final rect = Rect.fromLTWH(
      size.width - right - barWidth,
      top,
      barWidth,
      barHeight,
    );
    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: palette == PointCloudPalette.grayscale
          ? const [Colors.black, Colors.white]
          : const [Color(0xFF4FC3F7), Color(0xFF69F0AE), Color(0xFFFF7043)],
      stops: palette == PointCloudPalette.grayscale
          ? null
          : const [0.0, 0.5, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white54,
    );
    _drawColorbarText(canvas, Offset(rect.left - 58, rect.top - 2), range.max);
    _drawColorbarText(
      canvas,
      Offset(rect.left - 58, rect.bottom - 12),
      range.min,
    );
  }

  void _drawColorbarText(Canvas canvas, Offset offset, double value) {
    final painter = TextPainter(
      text: TextSpan(
        text: value.toStringAsFixed(2),
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 54);
    painter.paint(canvas, offset);
  }

  void _drawAxis(
    Canvas canvas,
    ({Offset offset, double cameraZ}) Function(double x, double y, double z)
    project,
  ) {
    final origin = project(0, 0, 0).offset;
    final xAxis = project(axisScale, 0, 0).offset;
    final yAxis = project(0, axisScale, 0).offset;
    final zAxis = project(0, 0, axisScale).offset;
    final axisPaint = Paint()
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    axisPaint.color = const Color(0xFFFF5252);
    canvas.drawLine(origin, xAxis, axisPaint);
    axisPaint.color = const Color(0xFF69F0AE);
    canvas.drawLine(origin, yAxis, axisPaint);
    axisPaint.color = const Color(0xFF40C4FF);
    canvas.drawLine(origin, zAxis, axisPaint);
  }

  void _drawEmpty(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'No points in depth range',
        style: TextStyle(color: Colors.grey, fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2.0,
        (size.height - textPainter.height) / 2.0,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _PointCloudPainter oldDelegate) {
    return data != oldDelegate.data ||
        pointSize != oldDelegate.pointSize ||
        showAxis != oldDelegate.showAxis ||
        axisScale != oldDelegate.axisScale ||
        minDepth != oldDelegate.minDepth ||
        maxDepth != oldDelegate.maxDepth ||
        viewport != oldDelegate.viewport ||
        yaw != oldDelegate.yaw ||
        pitch != oldDelegate.pitch ||
        zoom != oldDelegate.zoom ||
        panOffset != oldDelegate.panOffset ||
        palette != oldDelegate.palette ||
        detectionPositions != oldDelegate.detectionPositions;
  }
}
