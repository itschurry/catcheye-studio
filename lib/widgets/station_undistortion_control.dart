import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/remote_capture_api_service.dart';

/// The key must include the device URL and camera ID so responses cannot cross sessions.
class StationUndistortionControl extends StatefulWidget {
  const StationUndistortionControl({
    super.key,
    required this.api,
    required this.settings,
    required this.cameraId,
    required this.blocked,
    this.observedEnabled,
    required this.onApplyingChanged,
  });

  final RemoteCaptureApiService api;
  final AppSettings settings;
  final String cameraId;
  final bool blocked;
  final bool? observedEnabled;
  final ValueChanged<bool> onApplyingChanged;

  @override
  State<StationUndistortionControl> createState() =>
      _StationUndistortionControlState();
}

class _StationUndistortionControlState
    extends State<StationUndistortionControl> {
  StationUndistortion? _mode;
  bool? _enabled;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StationUndistortionControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_loading &&
        _error == null &&
        widget.observedEnabled != null &&
        oldWidget.observedEnabled != widget.observedEnabled) {
      _enabled = widget.observedEnabled;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mode = await widget.api.fetchUndistortion(
        widget.settings,
        widget.cameraId,
      );
      if (!mounted) return;
      setState(() {
        _mode = mode;
        _enabled = mode.enabled;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _mode = null;
        _enabled = null;
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _change(bool enabled) async {
    if (_loading || widget.blocked) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    widget.onApplyingChanged(true);
    try {
      final mode = await widget.api.setUndistortion(
        widget.settings,
        widget.cameraId,
        enabled,
      );
      if (!mounted) return;
      setState(() {
        _mode = mode;
        _enabled = mode.enabled;
      });
    } catch (error) {
      if (!mounted) return;
      // A timeout may happen after the server applies the change. Require a GET
      // before another POST instead of guessing the state or replaying the POST.
      setState(() {
        _mode = null;
        _enabled = null;
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        widget.onApplyingChanged(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('왜곡 보정', style: TextStyle(fontSize: 12)),
            const Spacer(),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_enabled != null)
              Tooltip(
                message: '이 카메라의 송출·검출·저장·기준 촬영에 함께 적용됩니다',
                child: Switch(
                  value: _enabled!,
                  onChanged:
                      widget.blocked ||
                          !(_mode!.calibrationAvailable || _enabled!)
                      ? null
                      : _change,
                ),
              )
            else
              IconButton(
                tooltip: '보정 상태 다시 조회',
                onPressed: widget.blocked ? null : _load,
                icon: const Icon(Icons.refresh, size: 20),
              ),
          ],
        ),
        if (_error != null)
          Text(
            '보정 상태 확인 실패: $_error',
            style: const TextStyle(color: Colors.redAccent, fontSize: 11),
          ),
        if (_mode != null && !_mode!.calibrationAvailable)
          const Text(
            '보정 파일 없음',
            style: TextStyle(color: Colors.amber, fontSize: 11),
          ),
      ],
    );
  }
}
