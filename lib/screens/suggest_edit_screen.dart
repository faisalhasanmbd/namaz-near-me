import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show normalizePrayerTimingInput;
import '../models/mosque.dart';
import '../services/location_service.dart';
import '../services/otp_session.dart';

class SuggestEditScreen extends StatefulWidget {
  const SuggestEditScreen({super.key, required this.mosque});
  final Mosque mosque;
  @override
  State<SuggestEditScreen> createState() => _SuggestEditScreenState();
}

class _SuggestEditScreenState extends State<SuggestEditScreen> {
  static const _savedNameKey = 'saved_contributor_name';
  final _formKey = GlobalKey<FormState>();
  final _contributorNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _fajrController = TextEditingController();
  final _zuhrController = TextEditingController();
  final _asrController = TextEditingController();
  final _maghribController = TextEditingController();
  final _ishaController = TextEditingController();
  final _jumaController = TextEditingController();
  final _areaController = TextEditingController();
  final _nameController = TextEditingController();
  final _googleLocationController = TextEditingController();
  final _addressController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  bool _firebaseReady = false;
  bool _sendingOtp = false;
  bool _phoneVerified = false;
  bool _submitting = false;
  bool _otpSent = false;
  bool _capturingLocation = false;
  bool _isAtMosqueNow = false;
  String _issueType = 'timing';
  String? _verificationId;
  String? _pendingVerificationPhone;
  String? _verifiedPhone;
  String? _otpStatus;
  double? _capturedLat;
  double? _capturedLng;
  String? _capturedLocationText;

  @override
  void initState() {
    super.initState();
    _areaController.text = widget.mosque.area;
    _nameController.text = widget.mosque.name;
    _addressController.text = widget.mosque.address;
    if (widget.mosque.latitude != null) {
      _latitudeController.text = widget.mosque.latitude!.toStringAsFixed(6);
    }
    if (widget.mosque.longitude != null) {
      _longitudeController.text = widget.mosque.longitude!.toStringAsFixed(6);
    }
    _loadVerification();
    _loadSavedName();
  }

  Future<void> _loadVerification() async {
    final phone = await OtpSession.loadVerifiedPhone();
    if (phone == null || !mounted) return;
    setState(() {
      _verifiedPhone = phone;
      _phoneVerified = true;
      _phoneController.text = phone;
      _otpStatus = 'Mobile verified ✓';
    });
  }

  Future<void> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_savedNameKey)?.trim() ?? '';
    if (saved.isNotEmpty && mounted) {
      _contributorNameController.text = saved;
    }
  }

  Future<void> _saveName() async {
    final name = _contributorNameController.text.trim();
    if (name.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedNameKey, name);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _contributorNameController.dispose();
    _fajrController.dispose();
    _zuhrController.dispose();
    _asrController.dispose();
    _maghribController.dispose();
    _ishaController.dispose();
    _jumaController.dispose();
    _areaController.dispose();
    _nameController.dispose();
    _googleLocationController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickTime(TextEditingController ctrl, String label) async {
    TimeOfDay initial = TimeOfDay.now();
    if (ctrl.text.isNotEmpty) {
      final parts = ctrl.text.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) initial = TimeOfDay(hour: h, minute: m);
      }
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: label,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked != null) setState(() => ctrl.text = _formatTimeOfDay(picked));
  }

  Future<void> _ensureFirebase() async {
    if (_firebaseReady) return;
    await Firebase.initializeApp();
    _firebaseReady = true;
  }

  Future<void> _sendOtp() async {
    final phone = _normalizedPhone(_phoneController.text);
    if (phone == null) {
      setState(() => _otpStatus = 'Enter a valid mobile number.');
      return;
    }
    setState(() {
      _sendingOtp = true;
      _otpStatus = 'Sending OTP...';
    });
    try {
      await _ensureFirebase();
      _pendingVerificationPhone = phone;
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (cred) async {
          await FirebaseAuth.instance.signInWithCredential(cred);
          await _markPhoneVerified(_firebaseAuthPhone() ?? phone);
        },
        verificationFailed: (e) {
          if (!mounted) return;
          setState(() => _otpStatus = e.message ?? 'OTP failed.');
        },
        codeSent: (id, _) {
          if (!mounted) return;
          setState(() {
            _verificationId = id;
            _otpSent = true;
            _otpStatus = 'OTP sent to your number.';
          });
        },
        codeAutoRetrievalTimeout: (id) => _verificationId = id,
        timeout: const Duration(seconds: 60),
      );
    } catch (_) {
      setState(() => _otpStatus = 'OTP failed. Please try again.');
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_verificationId == null || _otpController.text.trim().isEmpty) return;
    try {
      final cred = PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: _otpController.text.trim());
      await FirebaseAuth.instance.signInWithCredential(cred);
      final phone = _firebaseAuthPhone() ?? _pendingVerificationPhone;
      if (phone == null) {
        throw FirebaseAuthException(code: 'missing-phone-number');
      }
      await _markPhoneVerified(phone);
    } catch (_) {
      if (mounted) {
        setState(() => _otpStatus = 'Invalid OTP. Please try again.');
      }
    }
  }

  Future<void> _markPhoneVerified(String phone) async {
    final normalized = _normalizedPhone(phone);
    if (normalized == null) {
      throw FirebaseAuthException(code: 'invalid-phone-number');
    }
    await OtpSession.saveVerifiedPhone(normalized);
    if (!mounted) return;
    setState(() {
      _verifiedPhone = normalized;
      _phoneVerified = true;
      _phoneController.text = normalized;
      _otpStatus = 'Mobile verified ✓';
    });
  }

  String? _normalizedPhone(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalized)) {
      return normalized;
    }
    return null;
  }

  String? _firebaseAuthPhone() {
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber;
    return phone == null ? null : _normalizedPhone(phone);
  }

  Future<void> _captureCurrentLocation() async {
    setState(() => _capturingLocation = true);
    final location = await LocationService().currentOrFallback();
    if (!mounted) return;
    if (!location.isCurrentLocation) {
      setState(() => _capturingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('GPS unavailable. Please enable location services.')));
      return;
    }
    setState(() {
      _capturedLat = location.latitude;
      _capturedLng = location.longitude;
      _capturedLocationText =
          '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
      _capturingLocation = false;
    });
  }

  void _syncCoordinatesFromGoogleText(String value) {
    final coords = _extractCoordinates(value);
    if (coords == null) return;
    setState(() {
      _latitudeController.text = coords.$1.toStringAsFixed(6);
      _longitudeController.text = coords.$2.toStringAsFixed(6);
    });
  }

  (double, double)? _extractCoordinates(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final patterns = [
      RegExp(r'@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)'),
      RegExp(
          r'[?&](?:q|query|ll|destination)=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)'),
      RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      final lat = double.tryParse(match.group(1) ?? '');
      final lng = double.tryParse(match.group(2) ?? '');
      if (_validCoordinates(lat, lng)) return (lat!, lng!);
    }
    return null;
  }

  String _suggestEditMosqueDocId(String mosqueName, String cityName) {
    String clean(String v) => v
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final base = '${clean(cityName)}-${clean(mosqueName)}'
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return base.isEmpty ? 'mosque-unknown' : base;
  }

  bool _validCoordinates(double? lat, double? lng) {
    return lat != null &&
        lng != null &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
  }

  double? _readCoordinate(TextEditingController controller) {
    return double.tryParse(controller.text.trim());
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_phoneVerified) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please verify your mobile number first.')));
      return;
    }
    await _saveName();
    final verifiedPhone =
        _verifiedPhone ?? await OtpSession.loadVerifiedPhone();
    if (!mounted) return;
    if (verifiedPhone == null || _normalizedPhone(verifiedPhone) == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please verify your mobile number again.')));
      return;
    }
    final isLocationEdit = _issueType == 'location' || _issueType == 'both';
    if ((_issueType == 'timing' || _issueType == 'both') &&
        _fajrController.text.trim().isEmpty &&
        _zuhrController.text.trim().isEmpty &&
        _asrController.text.trim().isEmpty &&
        _maghribController.text.trim().isEmpty &&
        _ishaController.text.trim().isEmpty &&
        _jumaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter at least one prayer time.')));
      return;
    }
    if (_issueType == 'name' && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter the correct mosque name.')));
      return;
    }
    final suggestedLat = _capturedLat ?? _readCoordinate(_latitudeController);
    final suggestedLng = _capturedLng ?? _readCoordinate(_longitudeController);
    final hasCoordinates = _validCoordinates(suggestedLat, suggestedLng);
    final hasAddress = _addressController.text.trim().isNotEmpty;
    final hasGoogleLocation = _googleLocationController.text.trim().isNotEmpty;
    if (isLocationEdit &&
        !hasCoordinates &&
        !hasAddress &&
        !hasGoogleLocation) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Please add coordinates, Google Maps link, or address.')));
      return;
    }
    if (_issueType == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Mosque?'),
          content: Text(
              'Permanently remove "${widget.mosque.name}"? This cannot be undone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete')),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    setState(() => _submitting = true);
    try {
      await _ensureFirebase();
      final contributorName = _contributorNameController.text.trim();
      final data = <String, dynamic>{
        'mosque_name': widget.mosque.name,
        'city': widget.mosque.city,
        'area': _areaController.text.trim().isNotEmpty
            ? _areaController.text.trim()
            : widget.mosque.area,
        if (contributorName.isNotEmpty) 'contributor_name': contributorName,
        if (isLocationEdit) 'address': _addressController.text.trim(),
        if (isLocationEdit)
          'google_location': _googleLocationController.text.trim(),
        'edit_type': isLocationEdit && _issueType == 'location'
            ? 'location'
            : 'timing_or_location',
        'issue_type': _issueType,
        if (isLocationEdit) 'is_at_mosque_now': _isAtMosqueNow,
        if (isLocationEdit && _capturedLat != null)
          'captured_latitude': _capturedLat,
        if (isLocationEdit && _capturedLng != null)
          'captured_longitude': _capturedLng,
        if (isLocationEdit && hasCoordinates)
          'suggested_latitude': suggestedLat,
        if (isLocationEdit && hasCoordinates)
          'suggested_longitude': suggestedLng,
        if (_issueType == 'delete')
          'deleted_by_phone': verifiedPhone
        else
          'suggested_by_phone': verifiedPhone,
        if (_issueType == 'name') 'suggested_name': _nameController.text.trim(),
        'status': 'submitted',
        'created_at': FieldValue.serverTimestamp(),
      };
      if (_issueType == 'timing' || _issueType == 'both') {
        final normalized = {
          'fajr':
              normalizePrayerTimingInput('fajr', _fajrController.text.trim()),
          'zohar':
              normalizePrayerTimingInput('zohar', _zuhrController.text.trim()),
          'asr': normalizePrayerTimingInput('asr', _asrController.text.trim()),
          'maghrib': normalizePrayerTimingInput(
              'maghrib', _maghribController.text.trim()),
          'isha':
              normalizePrayerTimingInput('isha', _ishaController.text.trim()),
          'juma':
              normalizePrayerTimingInput('juma', _jumaController.text.trim()),
        };
        normalized.forEach((key, value) {
          if (value != null) {
            data[key] = value;
          }
        });
      }
      await FirebaseFirestore.instance.collection('mosque_edits').add(data);

      // Timing edits: directly update mosques collection for instant visibility
      if (_issueType == 'timing' || _issueType == 'both') {
        final timingsToWrite = <String, String>{};
        final timingPairs = {
          'fajr': _fajrController.text.trim(),
          'zohar': _zuhrController.text.trim(),
          'asr': _asrController.text.trim(),
          'maghrib': _maghribController.text.trim(),
          'isha': _ishaController.text.trim(),
          'juma': _jumaController.text.trim(),
        };
        for (final entry in timingPairs.entries) {
          if (entry.value.isEmpty) continue;
          final v = normalizePrayerTimingInput(entry.key, entry.value);
          if (v != null) timingsToWrite[entry.key] = v;
        }
        if (timingsToWrite.isNotEmpty) {
          final city = widget.mosque.city ?? '';
          final docId = _suggestEditMosqueDocId(widget.mosque.name, city);
          await FirebaseFirestore.instance
              .collection('mosques')
              .doc(docId)
              .set({
            'name': widget.mosque.name,
            'city': city.isNotEmpty ? city : 'Moradabad',
            'area': _areaController.text.trim().isNotEmpty
                ? _areaController.text.trim()
                : widget.mosque.area,
            'timings': timingsToWrite,
            if (contributorName.isNotEmpty)
              'timing_verified_by_name': contributorName,
            'timing_verification_status': 'source_verified',
            'verified_by_phone_private': verifiedPhone,
            'timing_updated_at': FieldValue.serverTimestamp(),
            if (widget.mosque.placeId != null)
              'place_id': widget.mosque.placeId!,
          }, SetOptions(merge: true));
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Submitted! Timings updated instantly.')));
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Could not submit. Please check your internet connection.')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _timeField(TextEditingController ctrl, String label) {
    return TextFormField(
      controller: ctrl,
      readOnly: true,
      onTap: () => _pickTime(ctrl, label),
      decoration: InputDecoration(
        labelText: label,
        hintText: '--:--',
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.access_time, size: 16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showTiming = _issueType == 'timing' || _issueType == 'both';
    final showLocation = _issueType == 'location' || _issueType == 'both';
    final showDelete = _issueType == 'delete';

    return Scaffold(
      appBar: AppBar(title: const Text('Report an Issue')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // ── Mosque Info ──────────────────────────────────
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.mosque, size: 20, color: Color(0xFF0F7C68)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.mosque.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        Text(widget.mosque.area,
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 13)),
                      ]),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contributorNameController,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  hintText: 'Mohammad Ali',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline, size: 18),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),

              // ── What to fix ──────────────────────────────────
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _issueType,
                decoration: const InputDecoration(
                    labelText: 'What needs to be fixed?',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                items: const [
                  DropdownMenuItem(
                      value: 'timing',
                      child: Text('Prayer times are incorrect')),
                  DropdownMenuItem(
                      value: 'location',
                      child: Text('Mosque location is incorrect')),
                  DropdownMenuItem(
                      value: 'both',
                      child: Text('Both — timings and location')),
                  DropdownMenuItem(
                      value: 'name', child: Text('Mosque name is incorrect')),
                  DropdownMenuItem(
                      value: 'delete',
                      child: Text('Remove this mosque (duplicate / invalid)')),
                ],
                onChanged: (value) =>
                    setState(() => _issueType = value ?? _issueType),
              ),
              const SizedBox(height: 12),

              // ── Name field
              if (_issueType == 'name') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                      labelText: 'Correct mosque name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.edit, size: 18),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                ),
              ],
              // ── Delete warning
              if (_issueType == 'delete') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEF9A9A))),
                  child: const Row(children: [
                    Icon(Icons.warning_amber, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            'This mosque will be permanently removed. Only proceed if it is a duplicate or does not exist.',
                            style: TextStyle(fontSize: 13, color: Colors.red))),
                  ]),
                ),
              ],
              // ── Area field (always visible except delete) ─────
              if (_issueType != 'delete') ...[
                TextFormField(
                  controller: _areaController,
                  decoration: const InputDecoration(
                      labelText: 'Area / Locality',
                      hintText: 'e.g. Civil Lines, Sambhi Gate',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on_outlined, size: 18),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                ),
              ],
              const SizedBox(height: 12),

              // ── Timing section ───────────────────────────────
              if (showTiming) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF1F8E9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF81C784))),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.access_time,
                              color: Color(0xFF2E7D32), size: 16),
                          SizedBox(width: 6),
                          Text('Prayer Times',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2E7D32),
                                  fontSize: 13)),
                          Spacer(),
                          Text('Tap a field to pick time',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.black45)),
                        ]),
                        const SizedBox(height: 8),
                        // Row 1: Fajr, Zuhr, Asr
                        Row(children: [
                          Expanded(child: _timeField(_fajrController, 'Fajr')),
                          const SizedBox(width: 6),
                          Expanded(child: _timeField(_zuhrController, 'Zuhr')),
                          const SizedBox(width: 6),
                          Expanded(child: _timeField(_asrController, 'Asr')),
                        ]),
                        const SizedBox(height: 6),
                        // Row 2: Maghrib, Isha, Juma
                        Row(children: [
                          Expanded(
                              child: _timeField(_maghribController, 'Maghrib')),
                          const SizedBox(width: 6),
                          Expanded(child: _timeField(_ishaController, 'Isha')),
                          const SizedBox(width: 6),
                          Expanded(child: _timeField(_jumaController, 'Juma')),
                        ]),
                      ]),
                ),
                const SizedBox(height: 12),
              ],

              // ── Location section ─────────────────────────────
              if (showLocation) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF90CAF9))),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('I am at this mosque right now',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: const Text(
                              'Enable to capture your GPS coordinates for the mosque.',
                              style: TextStyle(fontSize: 11)),
                          value: _isAtMosqueNow,
                          onChanged: (value) =>
                              setState(() => _isAtMosqueNow = value ?? false),
                        ),
                        if (_isAtMosqueNow) ...[
                          Row(children: [
                            FilledButton.tonalIcon(
                                onPressed: _capturingLocation
                                    ? null
                                    : _captureCurrentLocation,
                                icon: Icon(
                                    _capturingLocation
                                        ? Icons.hourglass_empty
                                        : Icons.my_location,
                                    size: 16),
                                label: Text(
                                    _capturingLocation
                                        ? 'Capturing...'
                                        : 'Capture My Location',
                                    style: const TextStyle(fontSize: 13))),
                            if (_capturedLocationText != null) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_capturedLocationText!,
                                    style: const TextStyle(
                                        color: Color(0xFF0F7C68), fontSize: 11),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ]),
                          const SizedBox(height: 4),
                        ],
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _googleLocationController,
                          keyboardType: TextInputType.url,
                          onChanged: _syncCoordinatesFromGoogleText,
                          decoration: const InputDecoration(
                              labelText: 'Google Maps link or plus code',
                              hintText:
                                  'Paste maps.app.goo.gl link, @lat,lng, or plus code',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.link, size: 18),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12)),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _addressController,
                          minLines: 1,
                          maxLines: 2,
                          decoration: const InputDecoration(
                              labelText: 'Correct mosque address',
                              hintText: 'Nearby landmark / Google address',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.place_outlined, size: 18),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12)),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              controller: _latitudeController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true, signed: true),
                              decoration: const InputDecoration(
                                  labelText: 'Latitude',
                                  hintText: '28.838600',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _longitudeController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true, signed: true),
                              decoration: const InputDecoration(
                                  labelText: 'Longitude',
                                  hintText: '78.773300',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10)),
                            ),
                          ),
                        ]),
                      ]),
                ),
                const SizedBox(height: 12),
              ],

              // ── Phone + OTP ──────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFEAF7F3),
                    borderRadius: BorderRadius.circular(8)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(_phoneVerified ? Icons.verified : Icons.sms,
                            color: const Color(0xFF0F7C68), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneController,
                            enabled: !_phoneVerified && !_otpSent,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                                labelText: 'Mobile number',
                                hintText: '+919876543210',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10)),
                            validator: (v) => _normalizedPhone(v ?? '') == null
                                ? 'Enter full number with country code (+91...)'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                            onPressed:
                                _sendingOtp || _phoneVerified ? null : _sendOtp,
                            child: Text(
                                _sendingOtp
                                    ? '...'
                                    : _otpSent
                                        ? 'Resend'
                                        : 'Send OTP',
                                style: const TextStyle(fontSize: 13))),
                      ]),
                      if (_otpSent && !_phoneVerified) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              controller: _otpController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Enter OTP',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                              onPressed: _verifyOtp,
                              child: const Text('Verify')),
                        ]),
                      ],
                      if (_otpStatus != null) ...[
                        const SizedBox(height: 6),
                        Text(_otpStatus!,
                            style: TextStyle(
                                color: _phoneVerified
                                    ? const Color(0xFF0F7C68)
                                    : Colors.black54,
                                fontSize: 12)),
                      ],
                    ]),
              ),
              const SizedBox(height: 14),

              // ── Submit ───────────────────────────────────────
              FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  style: showDelete
                      ? FilledButton.styleFrom(backgroundColor: Colors.red)
                      : null,
                  icon: Icon(showDelete ? Icons.delete_forever : Icons.send,
                      size: 18),
                  label: Text(
                      _submitting
                          ? (showDelete ? 'Deleting...' : 'Submitting...')
                          : (showDelete
                              ? 'Delete This Mosque'
                              : 'Submit Report'),
                      style: const TextStyle(fontSize: 15))),
            ],
          ),
        ),
      ),
    );
  }
}
