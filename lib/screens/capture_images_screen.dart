import '../controllers/capture_browser_controller.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../widgets/capture_storage_summary.dart';
import '../widgets/ctrl_zoom_viewer.dart';

class CaptureImagesScreen extends StatefulWidget {
  const CaptureImagesScreen({super.key, this.isPhone = false});

  final bool isPhone;

  @override
  State<CaptureImagesScreen> createState() => _CaptureImagesScreenState();
}

class _CaptureImagesScreenState extends State<CaptureImagesScreen> {
  final _browser = CaptureBrowserController();
  Uint8List? _displayedBytes;
  final TransformationController _transformController =
      TransformationController();

  bool _fitToView = true;
  double _zoom = 1.0;

  @override
  void initState() {
    super.initState();
    _browser.addListener(_onBrowserChanged);
  }

  void _onBrowserChanged() {
    if (!mounted) return;
    if (_browser.imageBytes != null && _displayedBytes != _browser.imageBytes) {
      _displayedBytes = _browser.imageBytes;
      _zoom = 1;
      _transformController.value = Matrix4.identity();
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_browser.bind(context.watch<SettingsProvider>().settings)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_browser.reload());
      });
    }
  }

  @override
  void dispose() {
    _browser.dispose();
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(context),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 760) {
                return Column(
                  children: [
                    SizedBox(height: 240, child: _buildBrowserPanel(context)),
                    const Divider(height: 1),
                    Expanded(child: _buildPreview(context)),
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 320, child: _buildBrowserPanel(context)),
                  const VerticalDivider(width: 1),
                  Expanded(child: _buildPreview(context)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isPhone ? 12 : 16,
        vertical: widget.isPhone ? 6 : 8,
      ),
      color: colorScheme.surface,
      child: Row(
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 20,
            color: colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          const Text(
            '저장 이미지',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: '촬영',
                    child: IconButton.outlined(
                      icon: const Icon(Icons.camera_alt_outlined, size: 20),
                      onPressed: _browser.captureBusy
                          ? null
                          : _browser.captureAndShowLatest,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: '최신 이미지',
                    child: IconButton.outlined(
                      icon: const Icon(Icons.skip_next_outlined, size: 20),
                      onPressed: _browser.loading ? null : _browser.showLatest,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: '새로고침',
                    child: IconButton.outlined(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: _browser.loading ? null : _browser.reload,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: _fitToView ? '원본 크기' : '화면 맞춤',
                    child: IconButton.outlined(
                      icon: Icon(
                        _fitToView
                            ? Icons.aspect_ratio_outlined
                            : Icons.fit_screen_outlined,
                        size: 20,
                      ),
                      onPressed: _browser.selectedImage == null
                          ? null
                          : () => _setFit(!_fitToView),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: '축소',
                    child: IconButton.outlined(
                      icon: const Icon(Icons.remove, size: 20),
                      onPressed: _browser.selectedImage == null
                          ? null
                          : () => _setZoom(_zoom / 1.25),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${(_zoom * 100).round()}%',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: '확대',
                    child: IconButton.outlined(
                      icon: const Icon(Icons.add, size: 20),
                      onPressed: _browser.selectedImage == null
                          ? null
                          : () => _setZoom(_zoom * 1.25),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowserPanel(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_browser.loading &&
        _browser.dates.isEmpty &&
        _browser.storage == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_browser.error != null &&
        _browser.dates.isEmpty &&
        _browser.storage == null) {
      return _MessagePanel(icon: Icons.error_outline, text: _browser.error!);
    }

    return Container(
      color: colorScheme.surface,
      child: Column(
        children: [
          _browser.storage == null
              ? const _StorageUnavailableSummary()
              : CaptureStorageSummary(storage: _browser.storage!),
          if (_browser.dates.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: DropdownButtonFormField<String>(
                initialValue: _browser.selectedDate,
                decoration: const InputDecoration(
                  labelText: '날짜',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final date in _browser.dates)
                    DropdownMenuItem(
                      value: date.date,
                      child: Text('${date.date} (${date.count})'),
                    ),
                ],
                onChanged: (date) {
                  if (date != null) {
                    unawaited(_browser.loadImages(date));
                  }
                },
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _browser.images.isEmpty
                ? const _MessagePanel(
                    icon: Icons.image_not_supported_outlined,
                    text: '저장된 이미지가 없습니다',
                  )
                : ListView.separated(
                    itemCount: _browser.images.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final image = _browser.images[index];
                      final selected =
                          image.filename == _browser.selectedImage?.filename &&
                          image.date == _browser.selectedImage?.date;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        leading: const Icon(Icons.image_outlined, size: 20),
                        title: Text(
                          image.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'NotoSansKR'),
                        ),
                        subtitle: Text(
                          '${image.width} x ${image.height}  ${_formatBytes(image.sizeBytes)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _browser.selectImage(image),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final image = _browser.selectedImage;
    if (_browser.imageLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_browser.error != null && image == null) {
      return _MessagePanel(icon: Icons.error_outline, text: _browser.error!);
    }
    if (image == null || _browser.imageBytes == null) {
      return const _MessagePanel(
        icon: Icons.image_outlined,
        text: '이미지를 선택해 주세요',
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: const Color(0xFF101010),
            child: CtrlZoomViewer(
              transformationController: _transformController,
              minScale: 0.25,
              maxScale: 8,
              child: Center(
                child: Image.memory(
                  _browser.imageBytes!,
                  fit: _fitToView ? BoxFit.contain : BoxFit.none,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          right: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                '${image.date}  ${image.filename}  ${image.width} x ${image.height}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'NotoSansKR',
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _setFit(bool value) {
    setState(() {
      _fitToView = value;
      _zoom = 1.0;
    });
    _transformController.value = Matrix4.identity();
  }

  void _setZoom(double value) {
    final next = value.clamp(0.25, 8.0).toDouble();
    setState(() => _zoom = next);
    _transformController.value = Matrix4.diagonal3Values(next, next, 1.0);
  }

  String _formatBytes(int bytes) {
    const gib = 1024 * 1024 * 1024;
    const mib = 1024 * 1024;
    const kib = 1024;
    if (bytes >= gib) {
      return '${(bytes / gib).ceil()} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / mib).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / kib).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: Colors.grey),
          const SizedBox(height: 10),
          Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _StorageUnavailableSummary extends StatelessWidget {
  const _StorageUnavailableSummary();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF303030),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF4A4A4A)),
        ),
        child: const Row(
          children: [
            Icon(Icons.storage_outlined, size: 18, color: Colors.grey),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '저장 공간을 조회할 수 없습니다',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
