import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/board_ocr_service.dart';
import '../services/islamic_timing_service.dart';

class BoardScanButton extends StatefulWidget {
  const BoardScanButton({
    super.key,
    required this.fajrCtrl,
    required this.zoharCtrl,
    required this.asrCtrl,
    required this.maghribCtrl,
    required this.ishaCtrl,
    required this.jumaCtrl,
    required this.timingService,
    this.onLocationCaptured,
  });

  final TextEditingController fajrCtrl;
  final TextEditingController zoharCtrl;
  final TextEditingController asrCtrl;
  final TextEditingController maghribCtrl;
  final TextEditingController ishaCtrl;
  final TextEditingController jumaCtrl;
  final IslamicTimingService timingService;
  final void Function(double lat, double lng)? onLocationCaptured;

  @override
  State<BoardScanButton> createState() => _BoardScanButtonState();
}

class _BoardScanButtonState extends State<BoardScanButton> {
  bool _scanning = false;
  String? _statusMessage;

  Future<void> _scan(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1800,
    );
    if (picked == null) return;

    setState(() {
      _scanning = true;
      _statusMessage = null;
    });

    try {
      final file = File(picked.path);
      final result = await BoardOcrService.extractFromImage(file);

      if (!mounted) return;

      int filled = 0;
      void fill(String key, TextEditingController ctrl) {
        final val = result[key];
        if (val != null && val.isNotEmpty) {
          ctrl.text = val;
          filled++;
        }
      }

      fill('fajr', widget.fajrCtrl);
      fill('zohar', widget.zoharCtrl);
      fill('asr', widget.asrCtrl);
      fill('maghrib', widget.maghribCtrl);
      fill('isha', widget.ishaCtrl);
      fill('juma', widget.jumaCtrl);

      setState(() {
        _scanning = false;
        _statusMessage = filled > 0
            ? '$filled timing${filled == 1 ? '' : 's'} detected. Please verify.'
            : 'No timings detected. Enter manually.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _statusMessage = 'Scan failed. Enter timings manually.';
      });
    }
  }

  void _showSourcePicker() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined,
                    color: Color(0xFF0F7C68)),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _scan(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined,
                    color: Color(0xFF0F7C68)),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _scan(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0F7C68);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _scanning ? null : _showSourcePicker,
            style: OutlinedButton.styleFrom(
              foregroundColor: teal,
              side: const BorderSide(color: teal, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _scanning
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: teal,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Scanning...',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PrayerTimeIcon(),
                      SizedBox(width: 10),
                      Text(
                        'Scan Timing Board',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (_statusMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              _statusMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: _statusMessage!.contains('detected') &&
                        !_statusMessage!.startsWith('No')
                    ? teal
                    : Colors.black54,
              ),
            ),
          ),
      ],
    );
  }
}

// Prayer-time icon: mosque dome + clock badge, matching Shutterstock style.
class _PrayerTimeIcon extends StatelessWidget {
  const _PrayerTimeIcon();

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0F7C68);
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFE6F3F1),
              shape: BoxShape.circle,
            ),
          ),
          const Positioned(
            top: 4,
            child: Icon(Icons.mosque, size: 20, color: teal),
          ),
          Positioned(
            bottom: 1,
            right: 1,
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.schedule, size: 10, color: teal),
            ),
          ),
        ],
      ),
    );
  }
}
