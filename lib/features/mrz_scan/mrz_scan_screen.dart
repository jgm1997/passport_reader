import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:passport_reader/core/mrz/mrz_key.dart';
import 'package:passport_reader/core/mrz/mrz_ocr_extractor.dart';
import 'package:passport_reader/features/mrz_entry/manual_entry_screen.dart';
import 'package:passport_reader/features/mrz_scan/camera_frame_converter.dart';
import 'package:passport_reader/features/nfc/ready_to_scan_screen.dart';

class MrzScanScreen extends StatefulWidget {
  const MrzScanScreen({super.key});

  @override
  State<MrzScanScreen> createState() => _MrzScanScreenState();
}

class _MrzScanScreenState extends State<MrzScanScreen>
    with WidgetsBindingObserver {
  static const _minFrameInterval = Duration(milliseconds: 300);
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  CameraController? _controller;
  bool _initializing = false;
  bool _processing = false;
  bool _done = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastCandidate;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
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
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await controller.startImageStream((image) => _onFrame(controller, image));

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
        _error == null &&
        !_done) {
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

  // --- Frame processing ---
  Future<void> _onFrame(CameraController controller, CameraImage image) async {
    // 1. Drop frames we don't want to process
    if (_processing || _done || !mounted) return;
    if (_controller != null && !identical(controller, _controller)) return;

    final now = DateTime.now();
    if (now.difference(_lastFrameAt) < _minFrameInterval) return;

    _processing = true;
    _lastFrameAt = now;

    try {
      // 2. Covert and recognize
      final input = inputImageFromCameraImage(
        image,
        camera: controller.description,
        deviceOrientation: controller.value.deviceOrientation,
      );
      if (input == null) return;

      final recognized = await _recognizer.processImage(input);
      final lines = [
        for (final block in recognized.blocks)
          for (final line in block.lines) line.text,
      ];

      // 3. Extract, then require two matching frames in a row
      final key = MrzOcrExtractor.extract(lines);
      if (key == null || !mounted || _done) return;

      final fingerprint =
          '${key.documentNumber}|${key.dateOfBirth}|${key.dateOfExpiry}';
      if (fingerprint != _lastCandidate) {
        _lastCandidate = fingerprint;
        return;
      }

      await _finish(controller, key);
    } catch (e) {
      // One bad frame must not kill the scanner. Log the type, never the content.
      debugPrint('MRZ frame skipped: ${e.runtimeType}');
    } finally {
      _processing = false;
    }
  }

  Future<void> _finish(CameraController controller, MrzKey key) async {
    _done = true;
    _lastCandidate = null;
    HapticFeedback.mediumImpact();

    try {
      await controller.stopImageStream();
    } catch (_) {
      // Already stopped or disposed: fine, we're leaving anyway
    }
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ReadyToScanScreen(mrzKey: key)),
    );
  }

  void _enterManually() {
    _done = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ManualEntryScreen()),
    );
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
          TextButton(
            onPressed: _enterManually,
            child: const Text('Enter details manually'),
          ),
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
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Looking for MRZ... hold steady and avoid glare.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _enterManually,
                child: const Text('Enter details manually instead'),
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
