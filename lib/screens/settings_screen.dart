import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/roi_config_provider.dart';
import '../providers/settings_provider.dart';
import '../services/process_manager_service.dart';

/// Settings screen

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer3<SettingsProvider, RoiConfigProvider, ProcessManagerService>(
      builder: (context, settingsProvider, roiProvider, processManager, _) {
        final settings = settingsProvider.settings;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Settings',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              _SectionCard(
                title: 'Device Connection',
                icon: Icons.router,
                children: [
                  _TextField(
                    label: 'Detector Base URL',
                    value: settings.detectorBaseUrl,
                    onChanged: settingsProvider.updateDetectorBaseUrl,
                  ),
                  const SizedBox(height: 12),
                  _TextField(
                    label: 'Stream Path / URL',
                    value: settings.streamPath,
                    onChanged: settingsProvider.updateStreamPath,
                  ),
                  const SizedBox(height: 12),
                  _TextField(
                    label: 'API Base Path',
                    value: settings.apiBasePath,
                    onChanged: settingsProvider.updateApiBasePath,
                  ),
                  const SizedBox(height: 12),
                  _InfoRow('Resolved Stream URL', settings.streamUri.toString()),
                  _InfoRow('Settings API', settings.buildApiUri('settings').toString()),
                  _InfoRow('ROI API', settings.buildApiUri('roi').toString()),
                ],
              ),
              const SizedBox(height: 16),

              _SectionCard(
                title: 'Detector',
                icon: Icons.model_training,
                children: [
                  _TextField(
                    label: 'Camera Pipeline',
                    value: settings.cameraPipeline,
                    onChanged: settingsProvider.updateCameraPipeline,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  _PathField(
                    label: 'Model Parameter File (.param)',
                    value: settings.modelParamPath,
                    onChanged: settingsProvider.updateModelParamPath,
                    onBrowse: () => _browseFile(
                      context,
                      'Select Parameter File',
                      settingsProvider.updateModelParamPath,
                      extensions: ['param'],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PathField(
                    label: 'Model Binary File (.bin)',
                    value: settings.modelBinPath,
                    onChanged: settingsProvider.updateModelBinPath,
                    onBrowse: () => _browseFile(
                      context,
                      'Select Binary File',
                      settingsProvider.updateModelBinPath,
                      extensions: ['bin'],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PathField(
                    label: 'Metadata File (.yaml)',
                    value: settings.metadataPath,
                    onChanged: settingsProvider.updateMetadataPath,
                    onBrowse: () => _browseFile(
                      context,
                      'Select Metadata File',
                      settingsProvider.updateMetadataPath,
                      extensions: ['yaml', 'yml'],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PathField(
                    label: 'ROI Config File (.json)',
                    value: settings.roiConfigPath,
                    onChanged: settingsProvider.updateRoiConfigPath,
                    onBrowse: () => _browseFile(
                      context,
                      'Select ROI Config File',
                      (path) {
                        settingsProvider.updateRoiConfigPath(path);
                        roiProvider.loadFromFile(path);
                      },
                      extensions: ['json'],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable ROI'),
                    subtitle: const Text('Apply ROI intrusion detection on device'),
                    value: settings.roiEnabled,
                    onChanged: settingsProvider.updateRoiEnabled,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto Reload ROI'),
                    subtitle: const Text('Reload ROI file when detector sees it change'),
                    value: settings.roiAutoReload,
                    onChanged: settingsProvider.updateRoiAutoReload,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Render Preview'),
                    subtitle: const Text('Leave detector-side preview rendering enabled'),
                    value: settings.renderPreview,
                    onChanged: settingsProvider.updateRenderPreview,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Filter By Class'),
                    subtitle: const Text('Limit ROI checks to one class id'),
                    value: settings.filterByClass,
                    onChanged: settingsProvider.updateFilterByClass,
                  ),
                  const SizedBox(height: 8),
                  _NumberField(
                    label: 'Filter Class ID',
                    value: settings.filterClassId,
                    onChanged: settingsProvider.updateFilterClassId,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _SectionCard(
                title: 'Remote Sync',
                icon: Icons.sync_alt,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text('Load From Device'),
                        onPressed: processManager.busy
                            ? null
                            : () => _pullSettings(context),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.upload),
                        label: const Text('Apply To Device'),
                        onPressed: processManager.busy
                            ? null
                            : () => _pushSettings(context),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh Status'),
                        onPressed: processManager.busy
                            ? null
                            : () => processManager.refreshStatus(settings),
                      ),
                    ],
                  ),
                  if (processManager.statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      processManager.statusMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: processManager.status == GuardProcessStatus.error
                            ? Colors.red.shade300
                            : Colors.grey.shade300,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              _SectionCard(
                title: 'ROI Config Preview',
                icon: Icons.preview,
                children: [
                  _InfoRow('Camera ID', roiProvider.config.cameraId),
                  _InfoRow(
                    'Image Size',
                    '${roiProvider.config.imageWidth} × ${roiProvider.config.imageHeight}',
                  ),
                  _InfoRow('Zone Count', '${roiProvider.config.allowedZones.length}'),
                  _InfoRow(
                    'Active Zones',
                    '${roiProvider.config.allowedZones.where((z) => z.enabled).length}',
                  ),
                  if (roiProvider.filePath != null)
                    _InfoRow('Loaded Source', roiProvider.filePath!),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pullSettings(BuildContext context) async {
    final processManager = context.read<ProcessManagerService>();
    final settingsProvider = context.read<SettingsProvider>();
    try {
      final remoteSettings = await processManager.pullSettings(settingsProvider.settings);
      settingsProvider.applyRemoteSettings(remoteSettings);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device settings loaded')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load settings: $e')),
        );
      }
    }
  }

  Future<void> _pushSettings(BuildContext context) async {
    final processManager = context.read<ProcessManagerService>();
    final settings = context.read<SettingsProvider>().settings;
    try {
      await processManager.pushSettings(settings);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device settings updated')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update settings: $e')),
        );
      }
    }
  }

  Future<void> _browseFile(
    BuildContext context,
    String title,
    ValueChanged<String> onSelected, {
    List<String>? extensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: title,
      type: extensions != null ? FileType.custom : FileType.any,
      allowedExtensions: extensions,
    );
    if (result != null && result.files.single.path != null) {
      onSelected(result.files.single.path!);
    }
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _PathField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onBrowse;

  const _PathField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onBrowse,
  });

  @override
  State<_PathField> createState() => _PathFieldState();
}

class _PathFieldState extends State<_PathField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _PathField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            onChanged: widget.onChanged,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: 'Browse',
          onPressed: widget.onBrowse,
        ),
      ],
    );
  }
}

class _TextField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int maxLines;

  const _TextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
  });

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _TextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      maxLines: widget.maxLines,
      onChanged: widget.onChanged,
    );
  }
}

class _NumberField extends StatefulWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextValue = '${widget.value}';
    if (nextValue != _controller.text && !_focusNode.hasFocus) {
      _controller.text = nextValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      onChanged: (value) => widget.onChanged(int.tryParse(value) ?? 0),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
