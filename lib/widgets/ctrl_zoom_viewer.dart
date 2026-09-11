import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Requires Ctrl for wheel zoom while preserving touch pinch and drag gestures.
class CtrlZoomViewer extends StatefulWidget {
  const CtrlZoomViewer({
    super.key,
    required this.transformationController,
    required this.child,
    this.minScale = 1,
    this.maxScale = 16,
    this.panEnabled = true,
  });

  final TransformationController transformationController;
  final Widget child;
  final double minScale;
  final double maxScale;
  final bool panEnabled;

  @override
  State<CtrlZoomViewer> createState() => _CtrlZoomViewerState();
}

class _CtrlZoomViewerState extends State<CtrlZoomViewer> {
  bool _controlPressed = HardwareKeyboard.instance.isControlPressed;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  bool _onKeyEvent(KeyEvent event) {
    final pressed = HardwareKeyboard.instance.isControlPressed;
    if (_controlPressed != pressed) {
      setState(() => _controlPressed = pressed);
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: (event) {
      if (event is PointerScrollEvent &&
          _controlPressed &&
          event.scrollDelta.dy != 0) {
        // Ctrl+wheel belongs to the image, not the containing page.
        GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
      }
    },
    child: InteractiveViewer(
      transformationController: widget.transformationController,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      panEnabled: widget.panEnabled,
      trackpadScrollCausesScale: true,
      // InteractiveViewer computes wheel scale as exp(-delta / scaleFactor).
      // Infinite sensitivity denominator leaves wheel scale at 1 without
      // disabling touch pinch or consuming the containing page's scroll.
      scaleFactor: _controlPressed
          ? kDefaultMouseScrollToScaleFactor
          : double.infinity,
      child: widget.child,
    ),
  );
}
