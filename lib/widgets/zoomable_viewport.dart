import 'package:flutter/material.dart';

import 'ctrl_zoom_viewer.dart';

/// Transforms the image and its overlays together, preserving child coordinates.
class ZoomableViewport extends StatefulWidget {
  const ZoomableViewport({
    super.key,
    required this.child,
    this.editable = false,
  });

  final Widget child;
  final bool editable;

  @override
  State<ZoomableViewport> createState() => _ZoomableViewportState();
}

class _ZoomableViewportState extends State<ZoomableViewport> {
  final _transform = TransformationController();
  bool _moveMode = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double factor, Size size) {
    final current = _transform.value;
    final scale = current.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(1.0, 16.0);
    final ratio = next / scale;
    final center = size.center(Offset.zero);
    _transform.value = Matrix4.diagonal3Values(next, next, 1)
      ..setEntry(0, 3, center.dx + (current.entry(0, 3) - center.dx) * ratio)
      ..setEntry(1, 3, center.dy + (current.entry(1, 3) - center.dy) * ratio);
    if (next == 1) _transform.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          CtrlZoomViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: 16,
            panEnabled: !widget.editable || _moveMode,
            child: IgnorePointer(
              ignoring: widget.editable && _moveMode,
              child: widget.child,
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Material(
              color: const Color(0xDD202020),
              borderRadius: BorderRadius.circular(6),
              child: ValueListenableBuilder<Matrix4>(
                valueListenable: _transform,
                builder: (context, matrix, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.editable)
                      IconButton(
                        tooltip: _moveMode
                            ? '편집 모드: 드래그로 편집'
                            : '이동 모드: 드래그로 이동, 두 손가락으로 확대·축소',
                        isSelected: _moveMode,
                        icon: const Icon(Icons.pan_tool_outlined, size: 18),
                        selectedIcon: const Icon(Icons.pan_tool, size: 18),
                        onPressed: () => setState(() => _moveMode = !_moveMode),
                      ),
                    IconButton(
                      tooltip: '축소',
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: matrix.getMaxScaleOnAxis() <= 1
                          ? null
                          : () => _zoom(1 / 1.25, constraints.biggest),
                    ),
                    TextButton(
                      onPressed: () => _transform.value = Matrix4.identity(),
                      child: Tooltip(
                        message: '화면 맞춤',
                        child: Text(
                          '${(matrix.getMaxScaleOnAxis() * 100).round()}%',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '확대',
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: matrix.getMaxScaleOnAxis() >= 16
                          ? null
                          : () => _zoom(1.25, constraints.biggest),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
