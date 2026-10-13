import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:image_picker/image_picker.dart';

/// A small image analyzer that keeps the image and inference on the device.
class ImageExample extends StatefulWidget {
  const ImageExample({super.key});

  @override
  State<ImageExample> createState() => _ImageExampleState();
}

class _ImageExampleState extends State<ImageExample> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _promptController = TextEditingController(
    text: 'Describe this image and extract any visible text.',
  );

  Uint8List? _imageBytes;
  String? _imageName;
  String _result = '';
  String _status = 'Checking vision support…';
  bool _supportsVision = false;
  bool _busy = false;

  LocalAiModel? _model;
  LocalAiSession? _session;

  bool get _canUseCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _checkCapabilities();
  }

  Future<void> _checkCapabilities() async {
    try {
      final capabilities = await LocalAi.capabilities();
      if (!mounted) return;
      setState(() {
        _supportsVision = capabilities.supportsVision;
        _status = capabilities.supportsVision
            ? 'Vision is available through ${capabilities.apiName}.'
            : 'This device/build does not expose image input.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Could not read capabilities: $error');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2048,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageName = image.name;
        _result = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Could not load the image: $error');
    }
  }

  Future<LocalAiSession> _openSession() async {
    await _session?.close();
    _session = null;

    _model ??= await LocalAiModel.create(maxTokens: 4096, supportImage: true);
    return _session = await _model!.openSession(
      temperature: 0.1,
      maxOutputTokens: 1000,
      systemInstruction: '''
You analyze images on device. Follow the user's extraction instructions
precisely. Describe only details supported by the image and clearly identify
anything that is unreadable or uncertain. Honor the requested output format.
''',
    );
  }

  Future<void> _analyzeImage() async {
    final bytes = _imageBytes;
    final prompt = _promptController.text.trim();
    if (bytes == null || prompt.isEmpty || _busy || !_supportsVision) return;

    setState(() {
      _busy = true;
      _result = '';
      _status = 'Preparing the on-device model…';
    });

    try {
      await LocalAi.ensureReady();
      final session = await _openSession();
      await session.addImage(bytes);
      await session.addQueryChunk(prompt);
      final raw = await session.getResponse();
      if (!mounted) return;
      setState(() {
        _result = raw.trim();
        _status = 'Analysis finished. Review the result before using it.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Extraction failed: $error';
        _result = '';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    // The model owns and closes its sessions.
    final model = _model;
    if (model != null) unawaited(model.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = _imageBytes;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Image analysis',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose or photograph an image, then tell the local vision model '
          'what to describe or extract. No image is uploaded by this example.',
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  _supportsVision ? Icons.visibility : Icons.visibility_off,
                  color: _supportsVision ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_status)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _promptController,
          enabled: !_busy,
          minLines: 2,
          maxLines: 6,
          textInputAction: TextInputAction.newline,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'What should the model extract?',
            hintText: 'For example: List every product and price as JSON.',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose image'),
            ),
            if (_canUseCamera)
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take photo'),
              ),
            FilledButton.icon(
              onPressed:
                  imageBytes != null &&
                      _promptController.text.trim().isNotEmpty &&
                      _supportsVision &&
                      !_busy
                  ? _analyzeImage
                  : null,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(_busy ? 'Analyzing…' : 'Analyze image'),
            ),
          ],
        ),
        if (imageBytes != null) ...[
          const SizedBox(height: 16),
          Text(_imageName ?? 'Selected image'),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(imageBytes, height: 280, fit: BoxFit.contain),
          ),
        ],
        if (_result.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Model response',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                _result,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
