import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/frame_receiver_service.dart';

class PointCloudViewport {
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  const PointCloudViewport({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
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

    for (var i = 0; i < data.pointCount; i++) {
      final z = data.zAt(i);
      if (z < depthLow || z > depthHigh) continue;

      final x = data.xAt(i);
      final displayY = -data.yAt(i);
      minX = minX == null ? x : math.min(minX, x);
      maxX = maxX == null ? x : math.max(maxX, x);
      minY = minY == null ? displayY : math.min(minY, displayY);
      maxY = maxY == null ? displayY : math.max(maxY, displayY);
    }

    if (minX == null || maxX == null || minY == null || maxY == null) {
      return null;
    }

    final rangeX = math.max(maxX - minX, 1.0);
    final rangeY = math.max(maxY - minY, 1.0);
    final padX = rangeX * paddingRatio;
    final padY = rangeY * paddingRatio;

    return PointCloudViewport(
      minX: minX - padX,
      maxX: maxX + padX,
      minY: minY - padY,
      maxY: maxY + padY,
    );
  }
}

class PointCloudViewer extends StatelessWidget {
  final PointCloudData data;
  final double pointSize;
  final bool showAxis;
  final double axisScale;
  final double minDepth;
  final double maxDepth;
  final PointCloudViewport? viewport;

  const PointCloudViewer({
    super.key,
    required this.data,
    required this.pointSize,
    required this.showAxis,
    required this.axisScale,
    required this.minDepth,
    required this.maxDepth,
    this.viewport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: CustomPaint(
        painter: _PointCloudPainter(
          data: data,
          pointSize: pointSize,
          showAxis: showAxis,
          axisScale: axisScale,
          minDepth: minDepth,
          maxDepth: maxDepth,
          viewport: viewport,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PointCloudPainter extends CustomPainter {
  final PointCloudData data;
  final double pointSize;
  final bool showAxis;
  final double axisScale;
  final double minDepth;
  final double maxDepth;
  final PointCloudViewport? viewport;

  const _PointCloudPainter({
    required this.data,
    required this.pointSize,
    required this.showAxis,
    required this.axisScale,
    required this.minDepth,
    required this.maxDepth,
    this.viewport,
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
    final scale = math.min(size.width / rangeX, size.height / rangeY) * 0.9;
    final offset = Offset(
      (size.width - rangeX * scale) / 2.0,
      (size.height - rangeY * scale) / 2.0,
    );

    Offset project(double x, double y) {
      final displayY = -y;
      return Offset(
        offset.dx + (x - activeViewport.minX) * scale,
        size.height - (offset.dy + (displayY - activeViewport.minY) * scale),
      );
    }

    if (showAxis) {
      _drawAxis(canvas, project, scale);
    }

    final depthRange = math.max(depthHigh - depthLow, 1.0);
    final paint = Paint()..style = PaintingStyle.fill;
    final radius = math.max(pointSize, 0.5);
    for (var i = 0; i < data.pointCount; i++) {
      final z = data.zAt(i);
      if (z < depthLow || z > depthHigh) continue;

      final t = ((z - depthLow) / depthRange).clamp(0.0, 1.0);
      paint.color = Color.lerp(
        const Color(0xFF4FC3F7),
        const Color(0xFFFF7043),
        t,
      )!;
      canvas.drawCircle(project(data.xAt(i), data.yAt(i)), radius, paint);
    }
  }

  void _drawAxis(
    Canvas canvas,
    Offset Function(double x, double y) project,
    double scale,
  ) {
    final origin = project(0, 0);
    final xAxis = project(axisScale, 0);
    final yAxis = project(0, axisScale);
    final axisPaint = Paint()
      ..strokeWidth = math.max(1.0, scale * 0.002)
      ..style = PaintingStyle.stroke;

    axisPaint.color = const Color(0xFFFF5252);
    canvas.drawLine(origin, xAxis, axisPaint);
    axisPaint.color = const Color(0xFF69F0AE);
    canvas.drawLine(origin, yAxis, axisPaint);
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
        viewport != oldDelegate.viewport;
  }
}
