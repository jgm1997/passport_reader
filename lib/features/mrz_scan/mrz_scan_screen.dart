import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:passport_reader/core/mrz/mrz_ocr_extractor.dart';
import 'package:passport_reader/features/nfc/ready_to_scan_screen.dart';

class MrzScanScreen extends StatefulWidget {
  const MrzScanScreen({super.key});

  @override
  State<MrzScanScreen> createState() => _MrzScanScreenState();
}

class _MrzScanScreenState extends State<MrzScanScreen>
    with WidgetsBindingObserver {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  CameraController? _controller;
  bool _initializing = false;
  bool _busy = false;
  String? _error;
  String _hint =
      'Fit the two lines at the bottom of the photo page inside the frame.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _recognizer.close();
    super.dispose();
  }

  // --- Camera Lifecycle ---
  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;
    setState(() => _error = null);

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('NoCamera', 'This device has no camera.');
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = _describeCameraError(e));
    } finally {
      _initializing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final old = _controller;
      if (old != null) {
        setState(() => _controller = null);
        old.dispose();
      }
    } else if (state == AppLifecycleState.resumed &&
        _controller == null &&
        _error == null) {
      _initCamera();
    }
  }

  String _describeCameraError(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'Camera access was denied. Allow it in Settings, '
            'or enter your details manually.';
      default:
        return 'The camera could not start (${e.code})';
    }
  }

  // --- Capture and OCR ---
  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _busy) return;

    setState(() {
      _busy = true;
      _hint = 'Reading...';
    });

    XFile? photo;
    try {
      photo = await controller.takePicture();
      final input = InputImage.fromFilePath(photo.path);
      final recognized = await _recognizer.processImage(input);

      final lines = [
        for (final block in recognized.blocks)
          for (final line in block.lines) line.text,
      ];
      final mrzKey = MrzOcrExtractor.extract(lines);

      if (!mounted) return;
      if (mrzKey == null) {
        setState(
          () => _hint = 'MRZ not found. Hold the phone steady, avoid glare, and try again',
        );
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ReadyToScanScreen(mrzKey: mrzKey)),
      );
    } on CameraException catch (e) {
      if (mounted) setState(() => _hint = _describeCameraError(e));
    } finally {
      // The photo contains the whole passport page: never leave it on disk
      if (photo != null) {
        try {
          await File(photo.path).delete();
        } catch (_) {
          // Already gone or not deletable: nothing else we can do.
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Scan the MRZ')),
      body: SafeArea(child: _error != null ? _buildError() : _buildCamera()),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            size: 72,
            color: Colors.white70,
          ),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _initCamera, child: const Text('Try again')),
        ],
      ),
    );
  }

  Widget _buildCamera() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: Center(
            child: CameraPreview(controller, child: const _MrzFrameOverlay()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _capture,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt_outlined),
                label: Text(_busy ? 'Reading...' : 'Capture'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A frame that shows the user where to place the MRZ
class _MrzFrameOverlay extends StatelessWidget {
  const _MrzFrameOverlay();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, 0.6),
      child: FractionallySizedBox(
        widthFactor: 0.92,
        heightFactor: 0.16,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
