import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show normalizePrayerTimingInput;
import '../providers/app_provider.dart';
import '../utils/mosque_utils.dart' show cityContributorDocId;
import '../utils/phone_utils.dart';
import '../models/mosque.dart';
import '../data/cities.dart';
import '../services/islamic_timing_service.dart';
import '../services/location_service.dart';
import '../services/otp_session.dart';
import '../services/prayer_time_validator.dart';
import '../widgets/board_scan_button.dart';

class SuggestEditScreen extends StatefulWidget {
  const SuggestEditScreen({super.key, required this.mosque});
  final Mosque mosque;
  @override
  State<SuggestEditScreen> createState() => _SuggestEditScreenState();
}

class _SuggestEditScreenState extends State<SuggestEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contributorNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _fajrController = TextEditingController();
  final _zoharController = TextEditingController();
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
  String _savedName = '';
  double? _capturedLat;
  double? _capturedLng;
  String? _capturedLocationText;
  // OTP cooldown — UX protection; real abuse prevention is handled by Firebase Auth
  int _otpCooldownSeconds = 0;
  Timer? _otpCooldownTimer;

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
  }

  Future<void> _loadVerification() async {
    final appState = context.read<AppState>();
    // AppState is authoritative (loaded at startup); OtpSession is the fallback
    final results = await Future.wait([
      OtpSession.loadVerifiedPhone(),
      OtpSession.loadName(),
    ]);
    final phone = appState.verifiedPhone ?? results[0];
    final savedName = appState.contributorName ?? results[1];
    if (!mounted) return;

    if (savedName != null && savedName.isNotEmpty) {
      _savedName = savedName;
      if (_contributorNameController.text.trim().isEmpty) {
        _contributorNameController.text = savedName;
      }
    }

    if (phone == null) return;

    // Only restore "verified" state if the Firebase Auth token also carries
    // this phone_number. If the token is from a different session (e.g. the
    // user reinstalled or the token was cleared), Firestore rules will deny
    // the write even though OtpSession still shows the cached phone.
    final firebasePhone = _firebaseAuthPhone();
    if (firebasePhone == phone) {
      setState(() {
        _verifiedPhone = phone;
        _phoneVerified = true;
        _phoneController.text = phone;
        _otpStatus = 'Mobile verified ✓';
      });
    } else {
      // Pre-fill the number so the user doesn't have to retype it,
      // but require a fresh OTP this session to get a valid token.
      setState(() {
        _phoneController.text = phone;
      });
    }
  }

  void _startOtpCooldown() {
    setState(() => _otpCooldownSeconds = 60);
    _otpCooldownTimer?.cancel();
    _otpCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _otpCooldownSeconds--;
        if (_otpCooldownSeconds <= 0) timer.cancel();
      });
    });
  }

  @override
  void dispose() {
    _otpCooldownTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    _contributorNameController.dispose();
    _fajrController.dispose();
    _zoharController.dispose();
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

  Future<void> _showChangeNameDialog() async {
    final ctrl = TextEditingController(text: _contributorNameController.text);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change your name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Your name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final newName = ctrl.text.trim();
      setState(() {
        _contributorNameController.text = newName;
        _savedName = newName;
      });
      await context.read<AppState>().setContributorName(newName);
      // Update leaderboard name in Firestore if phone is verified
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && _phoneVerified) {
        final cityName = widget.mosque.city ?? '';
        if (cityName.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('top_contributors')
              .doc(cityContributorDocId(cityName, user.uid))
              .set({'name': newName}, SetOptions(merge: true));
        }
      }
    }
  }

  Future<void> _updateFirebaseContributorName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.displayName?.trim() != trimmed) {
      try {
        await user.updateDisplayName(trimmed);
      } catch (_) {}
    }
  }

  // Links phone credential to anonymous session; falls back to sign-in if
  // the phone is already registered to another account.
  Future<void> _signInOrLink(PhoneAuthCredential cred) async {
    final current = FirebaseAuth.instance.currentUser;
    if (current != null && current.isAnonymous) {
      try {
        await current.linkWithCredential(cred);
        return;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use') rethrow;
      }
    }
    await FirebaseAuth.instance.signInWithCredential(cred);
  }

  Future<void> _sendOtp() async {
    if (_otpCooldownSeconds > 0) return;
    final phone = PhoneUtils.normalize(_phoneController.text);
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
          await _signInOrLink(cred);
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
          _startOtpCooldown();
        },
        codeAutoRetrievalTimeout: (id) => _verificationId = id,
        timeout: const Duration(seconds: 60),
      );
    } catch (_) {
      if (mounted) setState(() => _otpStatus = 'OTP failed. Please try again.');
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  bool _verifyingOtp = false;

  Future<void> _verifyOtp() async {
    if (_verificationId == null || _otpController.text.trim().isEmpty) return;
    if (mounted) setState(() => _verifyingOtp = true);
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text.trim(),
      );
      await _signInOrLink(cred);
      // Force-refresh the ID token so the phone_number claim is available
      // immediately for the Firestore verifiedPhone() rule check.
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final phone = _firebaseAuthPhone() ?? _pendingVerificationPhone;
      if (phone == null) {
        throw FirebaseAuthException(code: 'missing-phone-number');
      }
      await _markPhoneVerified(phone);
    } catch (_) {
      if (mounted) {
        setState(() => _otpStatus = 'Invalid OTP. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _verifyingOtp = false);
    }
  }

  Future<void> _markPhoneVerified(String phone) async {
    final normalized = PhoneUtils.normalize(phone);
    if (normalized == null) {
      throw FirebaseAuthException(code: 'invalid-phone-number');
    }
    await context.read<AppState>().markPhoneVerified(normalized);
    if (!mounted) return;
    setState(() {
      _verifiedPhone = normalized;
      _phoneVerified = true;
      _phoneController.text = normalized;
      _otpStatus = 'Mobile verified ✓';
    });
  }

  String? _firebaseAuthPhone() {
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber;
    return phone == null ? null : PhoneUtils.normalize(phone);
  }

  Future<void> _captureCurrentLocation() async {
    setState(() => _capturingLocation = true);
    final location = await LocationService().currentOrFallback();
    if (!mounted) return;
    if (!location.isCurrentLocation) {
      setState(() => _capturingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS unavailable. Please enable location services.'),
        ),
      );
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
        r'[?&](?:q|query|ll|destination)=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)',
      ),
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
    final base = '${clean(cityName)}-${clean(mosqueName)}'.replaceAll(
      RegExp(r'^-+|-+$'),
      '',
    );
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

  IslamicTimingService _timingServiceForMosque() {
    final lat = _capturedLat ??
        _readCoordinate(_latitudeController) ??
        widget.mosque.latitude;
    final lng = _capturedLng ??
        _readCoordinate(_longitudeController) ??
        widget.mosque.longitude;
    if (_validCoordinates(lat, lng)) {
      return IslamicTimingService(latitude: lat!, longitude: lng!);
    }

    CityInfo? city;
    final cityKey = (widget.mosque.city ?? '').trim().toLowerCase();
    for (final candidate in indianCities) {
      if (candidate.name.toLowerCase() == cityKey) {
        city = candidate;
        break;
      }
    }
    return city == null
        ? IslamicTimingService()
        : IslamicTimingService(
            latitude: city.latitude,
            longitude: city.longitude,
          );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_phoneVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please verify your mobile number first.'),
        ),
      );
      return;
    }
    await _ensureFirebase();
    await _updateFirebaseContributorName(_contributorNameController.text);
    final verifiedPhone =
        _verifiedPhone ?? await OtpSession.loadVerifiedPhone();
    if (!mounted) return;
    if (verifiedPhone == null || PhoneUtils.normalize(verifiedPhone) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please verify your mobile number again.'),
        ),
      );
      return;
    }
    // Guard: confirm Firebase Auth token actually carries phone_number before
    // writing to Firestore. If the token is from a different session the rule
    // will deny the write. Show a clear message and reset so the user can
    // re-verify without confusion.
    final firebasePhone = _firebaseAuthPhone();
    if (firebasePhone != verifiedPhone) {
      if (!mounted) return;
      setState(() {
        _phoneVerified = false;
        _verifiedPhone = null;
        _otpStatus = 'Session expired. Please verify OTP again.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Phone session expired. Please tap Send OTP to verify again.'),
        ),
      );
      return;
    }
    final isLocationEdit = _issueType == 'location' || _issueType == 'both';
    if ((_issueType == 'timing' || _issueType == 'both') &&
        _fajrController.text.trim().isEmpty &&
        _zoharController.text.trim().isEmpty &&
        _asrController.text.trim().isEmpty &&
        _maghribController.text.trim().isEmpty &&
        _ishaController.text.trim().isEmpty &&
        _jumaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one prayer time.')),
      );
      return;
    }
    if (_issueType == 'name' && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the correct mosque name.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add coordinates, Google Maps link, or address.',
          ),
        ),
      );
      return;
    }
    if (_issueType == 'timing' || _issueType == 'both') {
      final invalidTimingMessage = _invalidSubmittedTimingMessage(
        _normalizedTimingInputs(),
      );
      if (invalidTimingMessage != null) {
        await _showTimingValidationDialog(invalidTimingMessage);
        return;
      }
    }
    if (_issueType == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Mosque?'),
          content: Text(
            'Permanently remove "${widget.mosque.name}"? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    setState(() => _submitting = true);
    try {
      await _ensureFirebase();
      final contributorName = _contributorNameController.text.trim();
      final city = (widget.mosque.city ?? '').trim();
      final area = _areaController.text.trim().isNotEmpty
          ? _areaController.text.trim()
          : widget.mosque.area;
      final docId = widget.mosque.firestoreDocId ??
          _suggestEditMosqueDocId(widget.mosque.name, city);
      final mosqueRef =
          FirebaseFirestore.instance.collection('mosques').doc(docId);
      final existingMosqueSnap = await mosqueRef.get();
      final existingMosqueData = existingMosqueSnap.data();

      // Log to mosque_edits for audit history
      final logData = <String, dynamic>{
        'mosque_name': widget.mosque.name,
        'city': city,
        'area': area,
        if (contributorName.isNotEmpty) 'contributor_name': contributorName,
        if (isLocationEdit) 'address': _addressController.text.trim(),
        if (isLocationEdit)
          'google_location': _googleLocationController.text.trim(),
        'edit_type': _issueType == 'delete'
            ? 'delete'
            : (isLocationEdit && _issueType == 'location'
                ? 'location'
                : 'timing_or_location'),
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
        // Audit fields — score is awarded by Cloud Function, not client
        'submitted_by_uid': FirebaseAuth.instance.currentUser?.uid,
        'submittedAt': FieldValue.serverTimestamp(),
        'scoreAwarded': false,
        // Self-governance: edits go live immediately on phone verification.
        'status': 'live',
        'reportCount': 0,
        'created_at': FieldValue.serverTimestamp(),
      };

      // Build previousValue snapshot from the existing mosque document
      final previousValueMap = <String, dynamic>{};
      if (_issueType == 'timing' || _issueType == 'both') {
        final existing = existingMosqueData?['timings'];
        if (existing is Map) {
          for (final k in ['fajr', 'zohar', 'asr', 'maghrib', 'isha', 'juma']) {
            if (existing[k] != null) previousValueMap[k] = existing[k];
          }
        }
      }
      if (_issueType == 'name') {
        previousValueMap['name'] = existingMosqueData?['name'];
      }
      if (isLocationEdit) {
        if (existingMosqueData?['latitude'] != null) {
          previousValueMap['latitude'] = existingMosqueData!['latitude'];
        }
        if (existingMosqueData?['longitude'] != null) {
          previousValueMap['longitude'] = existingMosqueData!['longitude'];
        }
        if (existingMosqueData?['address'] != null) {
          previousValueMap['address'] = existingMosqueData!['address'];
        }
      }
      if (previousValueMap.isNotEmpty) {
        logData['previousValue'] = previousValueMap;
      }

      if (_issueType == 'timing' || _issueType == 'both') {
        final normalized = {
          'fajr': normalizePrayerTimingInput(
            'fajr',
            _fajrController.text.trim(),
          ),
          'zohar': normalizePrayerTimingInput(
            'zohar',
            _zoharController.text.trim(),
          ),
          'asr': normalizePrayerTimingInput('asr', _asrController.text.trim()),
          'maghrib': normalizePrayerTimingInput(
            'maghrib',
            _maghribController.text.trim(),
          ),
          'isha': normalizePrayerTimingInput(
            'isha',
            _ishaController.text.trim(),
          ),
          'juma': normalizePrayerTimingInput(
            'juma',
            _jumaController.text.trim(),
          ),
        };
        final newValueMap = <String, dynamic>{};
        normalized.forEach((key, value) {
          if (value != null) {
            logData[key] = value;
            newValueMap[key] = value;
          }
        });
        if (newValueMap.isNotEmpty) logData['newValue'] = newValueMap;
      }
      if (_issueType == 'name') {
        logData['newValue'] = {'name': _nameController.text.trim()};
      }
      if (isLocationEdit && hasCoordinates) {
        logData['newValue'] = {
          'latitude': suggestedLat,
          'longitude': suggestedLng
        };
      }

      await FirebaseFirestore.instance.collection('mosque_edits').add(logData);

      // Score is awarded by Cloud Function (autoApproveMosqueEdit) after
      // it validates the edit, preventing client-side score manipulation.

      final submittedName = _contributorNameController.text.trim();
      if (submittedName.isNotEmpty && mounted) {
        await context.read<AppState>().setContributorName(submittedName);
      }

      if (!mounted) return;
      final msg = _issueType == 'delete'
          ? 'JazakAllah! Mosque removed.'
          : 'JazakAllah! Changes submitted.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('permission')
                ? 'Permission denied. Please verify your phone first.'
                : 'Could not submit. Please check your internet connection.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Map<String, String> _normalizedTimingInputs() {
    final normalized = <String, String>{};
    final timingPairs = {
      'fajr': _fajrController.text.trim(),
      'zohar': _zoharController.text.trim(),
      'asr': _asrController.text.trim(),
      'maghrib': _maghribController.text.trim(),
      'isha': _ishaController.text.trim(),
      'juma': _jumaController.text.trim(),
    };
    for (final entry in timingPairs.entries) {
      if (entry.value.isEmpty) continue;
      final value = normalizePrayerTimingInput(entry.key, entry.value);
      if (value != null) normalized[entry.key] = value;
    }
    return normalized;
  }

  String? _invalidSubmittedTimingMessage(Map<String, String> timings) {
    final validator = PrayerTimeValidator(
      service: _timingServiceForMosque(),
      cityName: widget.mosque.city ?? '',
    );
    for (final entry in timings.entries) {
      final result = validator.validateDetailed(entry.key, entry.value);
      if (!result.isValid) return result.message;
    }
    return null;
  }

  Future<void> _showTimingValidationDialog(String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Check prayer time'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
      appBar: AppBar(title: const Text('Update Mosque Info')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // ── Mosque Info ──────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.mosque, size: 20, color: Color(0xFF0F7C68)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.mosque.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          widget.mosque.area,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'timing',
                    child: Text('Prayer times are incorrect'),
                  ),
                  DropdownMenuItem(
                    value: 'location',
                    child: Text('Mosque location is incorrect'),
                  ),
                  DropdownMenuItem(
                    value: 'both',
                    child: Text('Both — timings and location'),
                  ),
                  DropdownMenuItem(
                    value: 'name',
                    child: Text('Mosque name is incorrect'),
                  ),
                  DropdownMenuItem(
                    value: 'delete',
                    child: Text('Remove this mosque (duplicate / invalid)'),
                  ),
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
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
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
                    border: Border.all(color: const Color(0xFFEF9A9A)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This mosque will be permanently removed. Only proceed if it is a duplicate or does not exist.',
                          style: TextStyle(fontSize: 13, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
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
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
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
                    border: Border.all(color: const Color(0xFF81C784)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            color: Color(0xFF2E7D32),
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Prayer Times',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2E7D32),
                              fontSize: 13,
                            ),
                          ),
                          Spacer(),
                          Text(
                            'Tap a field to pick time',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      BoardScanButton(
                        fajrCtrl: _fajrController,
                        zoharCtrl: _zoharController,
                        asrCtrl: _asrController,
                        maghribCtrl: _maghribController,
                        ishaCtrl: _ishaController,
                        jumaCtrl: _jumaController,
                        timingService: _timingServiceForMosque(),
                        onLocationCaptured: (lat, lng) {
                          setState(() {
                            _capturedLat = lat;
                            _capturedLng = lng;
                            _latitudeController.text = lat.toStringAsFixed(6);
                            _longitudeController.text = lng.toStringAsFixed(6);
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      // Row 1: Fajr, Zuhr, Asr
                      Row(
                        children: [
                          Expanded(child: _timeField(_fajrController, 'Fajr')),
                          const SizedBox(width: 6),
                          Expanded(child: _timeField(_zoharController, 'Zuhr')),
                          const SizedBox(width: 6),
                          Expanded(child: _timeField(_asrController, 'Asr')),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Row 2: Maghrib, Isha, Jumu'ah
                      Row(
                        children: [
                          Expanded(
                            child: _timeField(_maghribController, 'Maghrib'),
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: _timeField(_ishaController, 'Isha')),
                          const SizedBox(width: 6),
                          Expanded(
                              child: _timeField(_jumaController, "Jumu'ah")),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Location section ─────────────────────────────
              if (showLocation) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF90CAF9)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text(
                          'I am at this mosque right now',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Enable to capture your GPS coordinates for the mosque.',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: _isAtMosqueNow,
                        onChanged: (value) =>
                            setState(() => _isAtMosqueNow = value ?? false),
                      ),
                      if (_isAtMosqueNow) ...[
                        Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _capturingLocation
                                  ? null
                                  : _captureCurrentLocation,
                              icon: Icon(
                                _capturingLocation
                                    ? Icons.hourglass_empty
                                    : Icons.my_location,
                                size: 16,
                              ),
                              label: Text(
                                _capturingLocation
                                    ? 'Capturing...'
                                    : 'Capture My Location',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            if (_capturedLocationText != null) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _capturedLocationText!,
                                  style: const TextStyle(
                                    color: Color(0xFF0F7C68),
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
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
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
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
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _latitudeController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Latitude',
                                hintText: '28.838600',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _longitudeController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Longitude',
                                hintText: '78.773300',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Contributor name + Phone + OTP ───────────────
              const Text(
                'Phone verification ensures only real people update timings.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _contributorNameController,
                readOnly: _savedName.isNotEmpty,
                decoration: InputDecoration(
                  labelText: 'Your name *',
                  hintText: 'Mohammad Ali',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person_outline, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  filled: _savedName.isNotEmpty,
                  fillColor:
                      _savedName.isNotEmpty ? const Color(0xFFF0F0F0) : null,
                  suffixIcon: _savedName.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Change name',
                          onPressed: _showChangeNameDialog,
                        )
                      : null,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter your name'
                    : null,
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7F3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _phoneVerified ? Icons.verified : Icons.sms,
                          color: const Color(0xFF0F7C68),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _phoneVerified
                                ? 'Mobile verified'
                                : _otpSent
                                    ? 'OTP sent'
                                    : 'Mobile verification',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (!_otpSent || _phoneVerified) ...[
                      TextFormField(
                        controller: _phoneController,
                        enabled: !_phoneVerified,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Mobile number',
                          hintText: '+919876543210',
                          prefixIcon: Icon(Icons.phone, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                        ),
                        validator: (v) => PhoneUtils.normalize(v ?? '') == null
                            ? 'Enter full number with country code (+91...)'
                            : null,
                      ),
                      if (!_phoneVerified) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: (_sendingOtp || _otpCooldownSeconds > 0)
                                ? null
                                : _sendOtp,
                            child: _sendingOtp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _otpCooldownSeconds > 0
                                        ? 'Resend in ${_otpCooldownSeconds}s'
                                        : 'Send OTP',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                          ),
                        ),
                      ],
                    ] else ...[
                      TextFormField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Enter OTP',
                          prefixIcon: Icon(Icons.sms, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _verifyingOtp ? null : _verifyOtp,
                          child: _verifyingOtp
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Verify'),
                        ),
                      ),
                      TextButton(
                        onPressed: (_sendingOtp || _otpCooldownSeconds > 0)
                            ? null
                            : _sendOtp,
                        child: Text(
                          _otpCooldownSeconds > 0
                              ? 'Resend in ${_otpCooldownSeconds}s'
                              : 'Resend OTP',
                        ),
                      ),
                    ],
                    if (_phoneVerified) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Mobile verified',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF0F7C68),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (_otpStatus != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _otpStatus!,
                        style: TextStyle(
                          color: _phoneVerified
                              ? const Color(0xFF0F7C68)
                              : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── Submit ───────────────────────────────────────
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                style: showDelete
                    ? FilledButton.styleFrom(backgroundColor: Colors.red)
                    : null,
                icon: Icon(
                  showDelete ? Icons.delete_forever : Icons.send,
                  size: 18,
                ),
                label: Text(
                  _submitting
                      ? (showDelete ? 'Deleting...' : 'Submitting...')
                      : (showDelete ? 'Delete This Mosque' : 'Save Changes'),
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
