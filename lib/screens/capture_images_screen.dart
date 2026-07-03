import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/remote_capture_api_service.dart';
import '../services/remote_capture_image_api_service.dart';

class CaptureImagesScreen extends StatefulWidget {
  const CaptureImagesScreen({super.key, this.isPhone = false});

  final bool isPhone;

  @override
  State<CaptureImagesScreen> createState() => _CaptureImagesScreenState();
}

class _CaptureImagesScreenState extends State<CaptureImagesScreen> {
  final RemoteCaptureImageApiService _api = RemoteCaptureImageApiService();
  final TransformationController _transformController =
      TransformationController();

  List<CaptureDateSummary> _dates = const [];
  List<CaptureImageItem> _images = const [];
  CaptureStorageInfo? _storage;
  CaptureImageItem? _selectedImage;
  Uint8List? _imageBytes;
  String? _selectedDate;
  String? _error;
  bool _loading = false;
  bool _imageLoading = false;
  bool _captureBusy = false;
  bool _fitToView = true;
  double _zoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_reload());
      }
    });
  }

  @override
  void dispose() {
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
            'Images',
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
                    message: 'Capture',
                    child: IconButton.outlined(
                      icon: const Icon(Icons.camera_alt_outlined, size: 20),
                      onPressed: _captureBusy ? null : _captureAndShowLatest,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Latest',
                    child: IconButton.outlined(
                      icon: const Icon(Icons.skip_next_outlined, size: 20),
                      onPressed: _loading ? null : _showLatest,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Refresh',
                    child: IconButton.outlined(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: _loading ? null : _reload,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: _fitToView ? 'Original size' : 'Fit to view',
                    child: IconButton.outlined(
                      icon: Icon(
                        _fitToView
                            ? Icons.aspect_ratio_outlined
                            : Icons.fit_screen_outlined,
                        size: 20,
                      ),
                      onPressed: _selectedImage == null
                          ? null
                          : () => _setFit(!_fitToView),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Zoom out',
                    child: IconButton.outlined(
                      icon: const Icon(Icons.remove, size: 20),
                      onPressed: _selectedImage == null
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
                    message: 'Zoom in',
                    child: IconButton.outlined(
                      icon: const Icon(Icons.add, size: 20),
                      onPressed: _selectedImage == null
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
    if (_loading && _dates.isEmpty && _storage == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _dates.isEmpty && _storage == null) {
      return _MessagePanel(icon: Icons.error_outline, text: _error!);
    }

    return Container(
      color: colorScheme.surface,
      child: Column(
        children: [
          _storage == null
              ? const _StorageUnavailableSummary()
              : _buildStorageSummary(_storage!),
          if (_dates.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedDate,
                decoration: const InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final date in _dates)
                    DropdownMenuItem(
                      value: date.date,
                      child: Text('${date.date} (${date.count})'),
                    ),
                ],
                onChanged: (date) {
                  if (date != null) {
                    unawaited(_loadImages(date));
                  }
                },
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _images.isEmpty
                ? const _MessagePanel(
                    icon: Icons.image_not_supported_outlined,
                    text: 'No images',
                  )
                : ListView.separated(
                    itemCount: _images.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final image = _images[index];
                      final selected =
                          image.filename == _selectedImage?.filename &&
                          image.date == _selectedImage?.date;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        leading: const Icon(Icons.image_outlined, size: 20),
                        title: Text(
                          image.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        subtitle: Text(
                          '${image.width} x ${image.height}  ${_formatBytes(image.sizeBytes)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectImage(image),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageSummary(CaptureStorageInfo storage) {
    final usedRatio = (storage.usedPercent / 100.0).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF303030),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF4A4A4A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Storage',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_formatBytes(storage.availableBytes)} free / ${_formatBytes(storage.totalBytes)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${storage.usedPercent.round()}% used',
                  maxLines: 1,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: usedRatio,
              minHeight: 6,
              borderRadius: BorderRadius.circular(999),
            ),
            const SizedBox(height: 8),
            Text(
              'Photos ${_formatBytes(storage.captureBytes)} · ${storage.captureCount} files',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final image = _selectedImage;
    if (_imageLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && image == null) {
      return _MessagePanel(icon: Icons.error_outline, text: _error!);
    }
    if (image == null || _imageBytes == null) {
      return const _MessagePanel(
        icon: Icons.image_outlined,
        text: 'Select image',
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: const Color(0xFF101010),
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.25,
              maxScale: 8,
              child: Center(
                child: Image.memory(
                  _imageBytes!,
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
                  fontFamily: 'monospace',
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

  Future<void> _reload() async {
    final previousDate = _selectedDate;
    final previousFilename = _selectedImage?.filename;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final settings = context.read<SettingsProvider>().settings;
      final response = await _api.fetchDates(settings);
      final dates = response.dates;
      if (!mounted) return;
      final nextDate =
          previousDate != null && dates.any((date) => date.date == previousDate)
          ? previousDate
          : dates.isEmpty
          ? null
          : dates.first.date;
      setState(() {
        _storage = response.storage;
        _dates = dates;
        _selectedDate = nextDate;
        _loading = false;
      });
      if (nextDate != null) {
        await _loadImages(nextDate, preferredFilename: previousFilename);
      } else {
        setState(() {
          _images = const [];
          _selectedImage = null;
          _imageBytes = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadImages(String date, {String? preferredFilename}) async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedDate = date;
    });
    try {
      final settings = context.read<SettingsProvider>().settings;
      final list = await _api.fetchImages(settings, date: date);
      if (!mounted) return;
      final selected = preferredFilename == null
          ? (list.items.isEmpty ? null : list.items.first)
          : list.items.cast<CaptureImageItem?>().firstWhere(
              (image) => image?.filename == preferredFilename,
              orElse: () => list.items.isEmpty ? null : list.items.first,
            );
      setState(() {
        _images = list.items;
        _selectedImage = selected;
        _imageBytes = null;
        _loading = false;
      });
      if (selected != null) {
        await _selectImage(selected);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _selectImage(CaptureImageItem image) async {
    setState(() {
      _selectedImage = image;
      _imageLoading = true;
      _error = null;
    });
    try {
      final bytes = await _api.fetchImageBytes(
        context.read<SettingsProvider>().settings,
        image,
      );
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageLoading = false;
      });
      _setFit(_fitToView);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _imageLoading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _showLatest() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = context.read<SettingsProvider>().settings;
      final latest = await _api.fetchLatest(settings);
      if (!mounted) return;
      await _loadImages(latest.date, preferredFilename: latest.filename);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _captureAndShowLatest() async {
    setState(() => _captureBusy = true);
    try {
      final settings = context.read<SettingsProvider>().settings;
      await RemoteCaptureApiService().requestCapture(settings);
      if (!mounted) return;
      await _showLatest();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _captureBusy = false);
      }
    }
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
                'Storage unavailable',
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
