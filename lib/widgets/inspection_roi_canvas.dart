import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/production.dart';

/// Uses only the displayed image area for input, excluding letterbox padding.
class InspectionRoiCanvas extends StatefulWidget {
  const InspectionRoiCanvas({
    super.key,
    required this.image,
    required this.imageSize,
    required this.roi,
    this.onChanged,
  });
  final Widget image;
  final Size imageSize;
  final InspectionRoi? roi;
  final ValueChanged<InspectionRoi>? onChanged;

  @override
  State<InspectionRoiCanvas> createState() => _InspectionRoiCanvasState();
}

class _InspectionRoiCanvasState extends State<InspectionRoiCanvas> {
  Offset? _start;
  Rect? _draft;

  Offset _normalized(Offset point, Size size) => Offset(
    (point.dx / size.width).clamp(0.0, 1.0),
    (point.dy / size.height).clamp(0.0, 1.0),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (widget.imageSize.isEmpty || !widget.imageSize.isFinite) {
        return const Center(child: Text('카메라 영상 크기를 확인할 수 없습니다'));
      }
      final scale = math.min(
        constraints.maxWidth / widget.imageSize.width,
        constraints.maxHeight / widget.imageSize.height,
      );
      final size = widget.imageSize * scale;
      final roi = widget.roi;
      final rect =
          _draft ??
          (roi == null
              ? null
              : Rect.fromLTWH(roi.x, roi.y, roi.width, roi.height));
      return Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: GestureDetector(
            key: const ValueKey('inspection-roi-image'),
            behavior: HitTestBehavior.opaque,
            onPanDown: widget.onChanged == null
                ? null
                : (details) {
                    _start = _normalized(details.localPosition, size);
                  },
            onPanUpdate: widget.onChanged == null
                ? null
                : (details) {
                    if (_start == null) return;
                    setState(
                      () => _draft = Rect.fromPoints(
                        _start!,
                        _normalized(details.localPosition, size),
                      ),
                    );
                  },
            onPanEnd: widget.onChanged == null
                ? null
                : (_) {
                    final draft = _draft;
                    setState(() {
                      _start = null;
                      _draft = null;
                    });
                    if (draft == null ||
                        draft.width * widget.imageSize.width < 2 ||
                        draft.height * widget.imageSize.height < 2) {
                      return;
                    }
                    widget.onChanged!(
                      InspectionRoi(
                        draft.left,
                        draft.top,
                        draft.width,
                        draft.height,
                      ),
                    );
                  },
            onPanCancel: () => setState(() {
              _start = null;
              _draft = null;
            }),
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.image,
                IgnorePointer(child: CustomPaint(painter: _RoiPainter(rect))),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _RoiPainter extends CustomPainter {
  const _RoiPainter(this.roi);
  final Rect? roi;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    final roi = this.roi;
    final guide = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (roi != null) {
      final rect = Rect.fromLTWH(
        roi.left * size.width,
        roi.top * size.height,
        roi.width * size.width,
        roi.height * size.height,
      );
      final shade = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(area)
        ..addRect(rect);
      canvas.drawPath(
        shade,
        Paint()..color = Colors.black.withValues(alpha: .55),
      );
      canvas.drawRect(rect, guide);
    }
    // Optical-position guide only; this does not certify robot pose or inspection OK.
    final center = area.center;
    canvas.drawLine(
      center - const Offset(12, 0),
      center + const Offset(12, 0),
      guide,
    );
    canvas.drawLine(
      center - const Offset(0, 12),
      center + const Offset(0, 12),
      guide,
    );
  }

  @override
  bool shouldRepaint(_RoiPainter oldDelegate) => oldDelegate.roi != roi;
}
