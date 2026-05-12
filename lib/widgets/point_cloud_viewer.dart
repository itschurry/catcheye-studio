import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/frame_receiver_service.dart';

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

      final x = -data.xAt(i);
      final displayY = -data.yAt(i);
      minX = minX == null ? x : math.min(minX, x);
      maxX = maxX == null ? x : math.max(maxX, x);
      minY = minY == null ? displayY : math.min(minY, displayY);
      maxY = maxY == null ? displayY : math.max(maxY, displayY);
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
            (widget.pitch + event.delta.dy * 0.01).clamp(-1.45, 1.45),
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
            ),
            child: const SizedBox.expand(),
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

  const _ProjectedPoint({
    required this.offset,
    required this.cameraZ,
    required this.sourceZ,
  });
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
  });

  @override
  void paint(Canvas canvas, Size size) {
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

    ({Offset offset, double cameraZ}) project(
      double x,
      double displayY,
      double z,
    ) {
      final tx = x - centerX;
      final ty = displayY - centerY;
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

    final depthRange = math.max(depthHigh - depthLow, 1.0);
    final paint = Paint()..style = PaintingStyle.fill;
    final radius = math.max(pointSize, 0.5);
    final projectedPoints = <_ProjectedPoint>[];
    for (var i = 0; i < data.pointCount; i++) {
      final z = data.zAt(i);
      if (z < depthLow || z > depthHigh) continue;
      final projected = project(-data.xAt(i), -data.yAt(i), z);
      projectedPoints.add(
        _ProjectedPoint(
          offset: projected.offset,
          cameraZ: projected.cameraZ,
          sourceZ: z,
        ),
      );
    }

    projectedPoints.sort((a, b) => a.cameraZ.compareTo(b.cameraZ));
    for (final point in projectedPoints) {
      final t = ((point.sourceZ - depthLow) / depthRange).clamp(0.0, 1.0);

      paint.color = Color.lerp(
        const Color(0xFF4FC3F7),
        const Color(0xFFFF7043),
        t,
      )!;
      canvas.drawCircle(point.offset, radius, paint);
    }
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
        panOffset != oldDelegate.panOffset;
  }
}
