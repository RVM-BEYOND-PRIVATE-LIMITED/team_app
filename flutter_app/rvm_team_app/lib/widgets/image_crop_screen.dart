import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

/// Opens a crop editor for a picked image and returns the cropped bytes, or
/// null when the person backs out. Pure Dart (no native crop plugin), so the
/// same screen works on every Android device without an extra manifest entry.
Future<Uint8List?> editImageBytes(BuildContext context, Uint8List bytes) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(builder: (_) => _ImageEditScreen(bytes: bytes)),
  );
}

class _ImageEditScreen extends StatefulWidget {
  const _ImageEditScreen({required this.bytes});
  final Uint8List bytes;

  @override
  State<_ImageEditScreen> createState() => _ImageEditScreenState();
}

class _ImageEditScreenState extends State<_ImageEditScreen> {
  final _controller = CropController();
  bool _cropping = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Edit photo'),
        actions: [
          TextButton(
            onPressed: _cropping ? null : _crop,
            child: _cropping
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'Done',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
      body: Crop(
        image: widget.bytes,
        controller: _controller,
        onCropped: (result) {
          if (!mounted) return;
          switch (result) {
            case CropSuccess(:final croppedImage):
              Navigator.of(context).pop(croppedImage);
            case CropFailure():
              setState(() => _cropping = false);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(
                    content: Text('Could not crop that photo.')));
          }
        },
        baseColor: Colors.black,
        maskColor: Colors.black.withValues(alpha: 0.55),
        radius: 12,
        progressIndicator:
            const CircularProgressIndicator(color: Colors.white),
      ),
      bottomNavigationBar: const SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Pinch to zoom · drag the box to crop',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 11.5),
          ),
        ),
      ),
    );
  }

  void _crop() {
    setState(() => _cropping = true);
    _controller.crop();
  }
}
