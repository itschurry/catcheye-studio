import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/frame_receiver_service.dart';

class PointCloudViewer extends StatelessWidget {
  final PointCloudData data;
  final double pointSize;
  final bool showAxis;
  final double axisScale;
  final double minDepth;
  final double maxDepth;

  const PointCloudViewer({
    super.key,
    required this.data,
    required this.pointSize,
    required this.showAxis,
    required this.axisScale,
    required this.minDepth,
    required this.maxDepth,
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

  const _PointCloudPainter({
    required this.data,
    required this.pointSize,
    required this.showAxis,
    required this.axisScale,
    required this.minDepth,
    required this.maxDepth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final depthLow = math.min(minDepth, maxDepth);
    final depthHigh = math.max(minDepth, maxDepth);
    final visiblePoints = data.points
        .where((p) => p.z >= depthLow && p.z <= depthHigh)
        .toList(growable: false);

    if (visiblePoints.isEmpty) {
      _drawEmpty(canvas, size);
      return;
    }

    var minX = visiblePoints.first.x;
    var maxX = visiblePoints.first.x;
    var minY = -visiblePoints.first.y;
    var maxY = -visiblePoints.first.y;
    for (final point in visiblePoints) {
      final displayY = -point.y;
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, displayY);
      maxY = math.max(maxY, displayY);
    }

    final rangeX = math.max(maxX - minX, 1.0);
    final rangeY = math.max(maxY - minY, 1.0);
    final scale = math.min(size.width / rangeX, size.height / rangeY) * 0.9;
    final offset = Offset(
      (size.width - rangeX * scale) / 2.0,
      (size.height - rangeY * scale) / 2.0,
    );

    Offset project(PointCloudPoint point) {
      final displayY = -point.y;
      return Offset(
        offset.dx + (point.x - minX) * scale,
        size.height - (offset.dy + (displayY - minY) * scale),
      );
    }

    if (showAxis) {
      _drawAxis(canvas, project, scale);
    }

    final depthRange = math.max(depthHigh - depthLow, 1.0);
    final paint = Paint()..style = PaintingStyle.fill;
    final radius = math.max(pointSize, 0.5);
    for (final point in visiblePoints) {
      final t = ((point.z - depthLow) / depthRange).clamp(0.0, 1.0);
      paint.color = Color.lerp(
        const Color(0xFF4FC3F7),
        const Color(0xFFFF7043),
        t,
      )!;
      canvas.drawCircle(project(point), radius, paint);
    }
  }

  void _drawAxis(
    Canvas canvas,
    Offset Function(PointCloudPoint point) project,
    double scale,
  ) {
    final origin = project(const PointCloudPoint(x: 0, y: 0, z: 0));
    final xAxis = project(PointCloudPoint(x: axisScale, y: 0, z: 0));
    final yAxis = project(PointCloudPoint(x: 0, y: axisScale, z: 0));
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
        maxDepth != oldDelegate.maxDepth;
  }
}
