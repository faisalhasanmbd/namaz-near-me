import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import '../services/otp_session.dart';
import '../utils/phone_utils.dart';
import '../services/prayer_time_validator.dart';
import '../services/islamic_timing_service.dart';
import '../utils/mosque_utils.dart';
import '../models/mosque.dart';
import '../data/cities.dart';
import '../providers/app_provider.dart';
import '../widgets/board_scan_button.dart';
import '../main.dart'
    show normalizePrayerTimingInput, formatStoredTime, formatPrayerStoredTime;

// Duplicated private helper (also present in main.dart for _mosqueFromFirestore).
String? _readString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return text;
}

// Helper that replicates _MosqueCard._distanceLabel from main.dart
// (cannot cross-reference a private static method from another file).
String _mosqueDistanceLabel(Mosque mosque) {
  if (!mosque.hasCoordinates) return 'location pending';
  final meters = mosque.distanceMeters;
  if (meters < 1000) return '${meters}m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

String _cleanContributorName(Object? value) {
  return _cleanContributorNameOrNull(value) ?? 'Namaz Volunteer';
}

String? _cleanContributorNameOrNull(Object? value) {
  final name = value?.toString().trim() ?? '';
  if (name.isEmpty || name.toLowerCase() == 'namaz volunteer') return null;
  return name;
}

class ContributorSignupScreen extends StatefulWidget {
  const ContributorSignupScreen({
    super.key,
    required this.cityName,
    required this.mosques,
  });

  final String cityName;
  final List<Mosque> mosques;

  @override
  State<ContributorSignupScreen> createState() =>
      _ContributorSignupScreenState();
}

class _ContributorSignupScreenState extends State<ContributorSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _areaController = TextEditingController();
  final _newMosqueController = TextEditingController();
  final _addressController = TextEditingController();
  final _fajrController = TextEditingController();
  final _zoharController = TextEditingController();
  final _asrController = TextEditingController();
  final _maghribController = TextEditingController();
  final _ishaController = TextEditingController();
  final _jumaController = TextEditingController();
  final _eidUlFitrController = TextEditingController();
  final _eidUlAzhaController = TextEditingController();
  final _otpController = TextEditingController();

  String _savedName = '';
  String _role = 'Volunteer';
  String _maslak = 'Not specified';
  String _mosqueMode = 'existing';
  bool _shareContributorDetails = true;
  Mosque? _selectedMosque;
  bool _firebaseReady = false;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  bool _submitting = false;
  bool _otpSent = false;
  bool _phoneVerified = false;
  String? _verificationId;
  String? _pendingVerificationPhone;
  String? _verifiedPhone;
  String? _otpStatusMessage;
  // OTP cooldown — ValueNotifier so timer ticks don't rebuild the whole screen
  final _otpCooldown = ValueNotifier<int>(0);
  Timer? _otpCooldownTimer;

  List<Mosque> get _availableMosques {
    final city = widget.cityName.toLowerCase().trim();
    return widget.mosques.where((mosque) {
      final mosqueCity = mosque.city?.toLowerCase().trim();
      return mosqueCity == null || mosqueCity == city;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _cityController.text = widget.cityName;
    _selectedMosque = null;
    _loadVerification();
  }

  Future<void> _updateFirebaseContributorName(String name) async {
    if (name.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Update Firebase Auth display name
    if (user.displayName?.trim() != name) {
      try {
        await user.updateDisplayName(name);
      } catch (_) {}
    }
    // Stamp name in top_contributors if it was "Namaz Volunteer" or missing
    try {
      final city = _cityController.text.trim();
      if (city.isEmpty) return;
      final docId = cityContributorDocId(city, user.uid);
      final ref =
          FirebaseFirestore.instance.collection('top_contributors').doc(docId);
      final snap = await ref.get();
      final currentName = snap.data()?['name'] as String? ?? '';
      if (!snap.exists ||
          currentName.isEmpty ||
          currentName == 'Namaz Volunteer') {
        await ref.set({'name': name}, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> _loadVerification() async {
    final appState = context.read<AppState>();
    // AppState.verifiedPhone is loaded at startup; fall back to OtpSession if
    // AppState hasn't populated yet (e.g., screen opened during cold start).
    final phone =
        appState.verifiedPhone ?? await OtpSession.loadVerifiedPhone();
    final savedName = appState.contributorName ?? await OtpSession.loadName();
    if (!mounted) return;

    if (savedName != null && savedName.isNotEmpty) {
      _savedName = savedName;
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = savedName;
      }
    }

    if (phone == null) return;
    setState(() {
      _verifiedPhone = phone;
      _phoneController.text = phone;
      _phoneVerified = true;
      _otpStatusMessage = 'Mobile verified for this session.';
    });
  }

  void _syncAreaFromSelectedMosque() {
    final mosque = _selectedMosque;
    if (mosque == null) return;
    _areaController.text = mosque.area;
  }

  void _startOtpCooldown() {
    _otpCooldown.value = 60;
    _otpCooldownTimer?.cancel();
    _otpCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _otpCooldown.value--;
      if (_otpCooldown.value <= 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _otpCooldownTimer?.cancel();
    _otpCooldown.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _areaController.dispose();
    _newMosqueController.dispose();
    _addressController.dispose();
    _fajrController.dispose();
    _zoharController.dispose();
    _asrController.dispose();
    _maghribController.dispose();
    _ishaController.dispose();
    _jumaController.dispose();
    _eidUlFitrController.dispose();
    _eidUlAzhaController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contribute — Add or Update Mosque')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const ClampingScrollPhysics(),
            children: [
              Text(
                'Update timings or add a new mosque',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'Verify your phone number, then update timings directly.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                readOnly: _savedName.isNotEmpty,
                decoration: InputDecoration(
                  labelText: 'Your name *',
                  helperText: 'Required for leaderboard and certificate.',
                  border: const OutlineInputBorder(),
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
                validator: _required,
              ),
              const SizedBox(height: 12),
              _OtpVerificationPanel(
                phoneController: _phoneController,
                otpController: _otpController,
                otpSent: _otpSent,
                phoneVerified: _phoneVerified,
                sendingOtp: _sendingOtp,
                verifyingOtp: _verifyingOtp,
                statusMessage: _otpStatusMessage,
                cooldownNotifier: _otpCooldown,
                onSendOtp: _sendOtp,
                onVerifyOtp: _verifyOtp,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Volunteer',
                    child: Text('Volunteer'),
                  ),
                  DropdownMenuItem(value: 'Muazzin', child: Text('Muazzin')),
                  DropdownMenuItem(value: 'Imam', child: Text('Imam')),
                ],
                onChanged: (value) => setState(() => _role = value ?? _role),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        border: OutlineInputBorder(),
                      ),
                      validator: _required,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _areaController,
                      decoration: const InputDecoration(
                        labelText: 'Area',
                        border: OutlineInputBorder(),
                      ),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _maslak,
                decoration: const InputDecoration(
                  labelText: 'School of Thought',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Not specified',
                    child: Text('Not specified'),
                  ),
                  DropdownMenuItem(value: 'Barelvi', child: Text('Barelvi')),
                  DropdownMenuItem(value: 'Deobandi', child: Text('Deobandi')),
                  DropdownMenuItem(
                    value: 'Ahl-e-Hadees',
                    child: Text('Ahl-e-Hadees'),
                  ),
                  DropdownMenuItem(value: 'Shia', child: Text('Shia')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (value) =>
                    setState(() => _maslak = value ?? _maslak),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'existing', label: Text('Existing')),
                  ButtonSegment(value: 'new', label: Text('New mosque')),
                ],
                selected: {_mosqueMode},
                onSelectionChanged: (values) {
                  setState(() {
                    _mosqueMode = values.first;
                    _selectedMosque = null;
                    _areaController.clear();
                  });
                },
              ),
              const SizedBox(height: 12),
              if (_mosqueMode == 'existing')
                _MosqueSelectorField(
                  selectedMosque: _selectedMosque,
                  mosqueCount: _availableMosques.length,
                  onTap: _pickExistingMosque,
                )
              else ...[
                TextFormField(
                  controller: _newMosqueController,
                  decoration: const InputDecoration(
                    labelText: 'New mosque name',
                    border: OutlineInputBorder(),
                  ),
                  validator: _mosqueMode == 'new' ? _required : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address / landmark',
                    border: OutlineInputBorder(),
                  ),
                  validator: _mosqueMode == 'new' ? _required : null,
                ),
              ],
              if (_mosqueMode == 'existing') ...[
                const SizedBox(height: 8),
                Text(
                  'Showing ${_availableMosques.length} masjids from ${widget.cityName} listing.',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  'New mosque will be submitted for ${widget.cityName}.',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Namaz timings',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              BoardScanButton(
                fajrCtrl: _fajrController,
                zoharCtrl: _zoharController,
                asrCtrl: _asrController,
                maghribCtrl: _maghribController,
                ishaCtrl: _ishaController,
                jumaCtrl: _jumaController,
                timingService: IslamicTimingService(),
              ),
              const SizedBox(height: 10),
              _TimingInputGrid(
                fajrController: _fajrController,
                zoharController: _zoharController,
                asrController: _asrController,
                maghribController: _maghribController,
                ishaController: _ishaController,
                jumaController: _jumaController,
              ),
              const SizedBox(height: 16),
              Text(
                'Eid Namaz timings',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              const Text(
                'Eid timings are annual — update once a year.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final p = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                          helpText: 'Eid ul Fitr',
                          builder: (context, child) => MediaQuery(
                            data: MediaQuery.of(
                              context,
                            ).copyWith(alwaysUse24HourFormat: false),
                            child: child!,
                          ),
                        );
                        if (p != null) {
                          _eidUlFitrController.text =
                              '${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}';
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Eid ul Fitr',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.access_time),
                        ),
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _eidUlFitrController,
                          builder: (context, value, _) => Text(
                            value.text.isEmpty
                                ? 'Tap to set'
                                : formatStoredTime(value.text),
                            style: TextStyle(
                              color: value.text.isEmpty
                                  ? Colors.black38
                                  : Colors.black87,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final p = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                          helpText: 'Eid ul Azha',
                          builder: (context, child) => MediaQuery(
                            data: MediaQuery.of(
                              context,
                            ).copyWith(alwaysUse24HourFormat: false),
                            child: child!,
                          ),
                        );
                        if (p != null) {
                          _eidUlAzhaController.text =
                              '${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}';
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Eid ul Azha',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.access_time),
                        ),
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _eidUlAzhaController,
                          builder: (context, value, _) => Text(
                            value.text.isEmpty
                                ? 'Tap to set'
                                : formatStoredTime(value.text),
                            style: TextStyle(
                              color: value.text.isEmpty
                                  ? Colors.black38
                                  : Colors.black87,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _shareContributorDetails,
                title: const Text('Publicly show my name and number'),
                subtitle: const Text(
                  'On by default for trust. Turn off if you do not want contact details public.',
                  style: TextStyle(fontSize: 12),
                ),
                onChanged: (value) =>
                    setState(() => _shareContributorDetails = value),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: const Icon(Icons.send),
                label: Text(_submitting ? 'Saving...' : 'Save Timings'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickExistingMosque() async {
    final selected = await showModalBottomSheet<Mosque>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MosquePickerSheet(
        mosques: _availableMosques,
        selectedMosque: _selectedMosque,
        cityName: widget.cityName,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedMosque = selected;
      _syncAreaFromSelectedMosque();
    });
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  Future<void> _ensureFirebase() async {
    if (_firebaseReady) return;
    await Firebase.initializeApp();
    _firebaseReady = true;
  }

  Future<void> _showChangeNameDialog() async {
    final ctrl = TextEditingController(text: _nameController.text);
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
        _nameController.text = newName;
        _savedName = newName;
      });
      await context.read<AppState>().setContributorName(newName);
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && _verifiedPhone != null) {
        final cityName = _cityController.text.trim();
        if (cityName.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('top_contributors')
              .doc(cityContributorDocId(cityName, user.uid))
              .set({'name': newName}, SetOptions(merge: true));
        }
      }
    }
  }

  Future<void> _markPhoneVerified(String phone) async {
    final normalized = PhoneUtils.normalize(phone);
    if (normalized == null) {
      throw FirebaseAuthException(code: 'invalid-phone-number');
    }
    await context.read<AppState>().markPhoneVerified(normalized);
    await _updateFirebaseContributorName(_nameController.text.trim());
    if (!mounted) return;
    setState(() {
      _verifiedPhone = normalized;
      _phoneController.text = normalized;
      _phoneVerified = true;
      _otpSent = true;
      _otpStatusMessage = 'Mobile verified for this session.';
    });
  }

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
    if (_otpCooldown.value > 0) return;
    final phone = PhoneUtils.normalize(_phoneController.text);
    if (phone == null) {
      setState(
        () => _otpStatusMessage = 'Enter a valid international phone number.',
      );
      return;
    }
    setState(() {
      _sendingOtp = true;
      _otpStatusMessage = 'Sending OTP...';
    });

    try {
      await _ensureFirebase();
      _pendingVerificationPhone = phone;
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (credential) async {
          await _signInOrLink(credential);
          await _markPhoneVerified(_firebaseAuthPhone() ?? phone);
        },
        verificationFailed: (error) {
          if (!mounted) return;
          setState(() {
            _otpStatusMessage =
                error.message ?? 'OTP failed. Check Firebase setup.';
          });
        },
        codeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _otpSent = true;
            _otpStatusMessage = 'OTP sent. Enter code to verify.';
          });
          _startOtpCooldown();
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _otpStatusMessage = 'OTP expired. Tap Resend.';
          });
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _otpStatusMessage =
              'Firebase is not configured yet. Add google-services.json and enable Phone Auth.';
        });
      }
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_verificationId == null || _otpController.text.trim().isEmpty) {
      setState(() => _otpStatusMessage = 'Enter the OTP code.');
      return;
    }

    setState(() {
      _verifyingOtp = true;
      _otpStatusMessage = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text.trim(),
      );
      await _signInOrLink(credential);
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final phone = _firebaseAuthPhone() ?? _pendingVerificationPhone;
      if (phone == null) {
        throw FirebaseAuthException(code: 'missing-phone-number');
      }
      await _markPhoneVerified(phone);
    } on FirebaseAuthException catch (error) {
      setState(() {
        _otpStatusMessage = error.message ?? 'Invalid OTP.';
      });
    } finally {
      if (mounted) setState(() => _verifyingOtp = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final contributorName = _cleanContributorName(_nameController.text);
    _nameController.text = contributorName;
    await _updateFirebaseContributorName(contributorName);
    if (!mounted) return;
    if (!_phoneVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verify mobile number with OTP first.')),
      );
      return;
    }
    final verifiedPhone =
        _verifiedPhone ?? context.read<AppState>().verifiedPhone;
    if (!mounted) return;
    if (verifiedPhone == null || PhoneUtils.normalize(verifiedPhone) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verify mobile number with OTP again.')),
      );
      return;
    }

    setState(() => _submitting = true);
    final mosqueName = _mosqueMode == 'existing'
        ? _selectedMosque?.name ?? 'Selected mosque'
        : _newMosqueController.text.trim();

    try {
      await _ensureFirebase();
      final db = FirebaseFirestore.instance;
      final submittedTimings = <String, String>{
        if (normalizePrayerTimingInput('fajr', _fajrController.text) != null)
          'fajr': normalizePrayerTimingInput('fajr', _fajrController.text)!,
        if (normalizePrayerTimingInput('zohar', _zoharController.text) != null)
          'zohar': normalizePrayerTimingInput('zohar', _zoharController.text)!,
        if (normalizePrayerTimingInput('asr', _asrController.text) != null)
          'asr': normalizePrayerTimingInput('asr', _asrController.text)!,
        if (normalizePrayerTimingInput('maghrib', _maghribController.text) !=
            null)
          'maghrib': normalizePrayerTimingInput(
            'maghrib',
            _maghribController.text,
          )!,
        if (normalizePrayerTimingInput('isha', _ishaController.text) != null)
          'isha': normalizePrayerTimingInput('isha', _ishaController.text)!,
        if (normalizePrayerTimingInput('juma', _jumaController.text) != null)
          'juma': normalizePrayerTimingInput('juma', _jumaController.text)!,
        if (normalizePrayerTimingInput(
              'eid_ul_fitr',
              _eidUlFitrController.text,
            ) !=
            null)
          'eid_ul_fitr': normalizePrayerTimingInput(
            'eid_ul_fitr',
            _eidUlFitrController.text,
          )!,
        if (normalizePrayerTimingInput(
              'eid_ul_azha',
              _eidUlAzhaController.text,
            ) !=
            null)
          'eid_ul_azha': normalizePrayerTimingInput(
            'eid_ul_azha',
            _eidUlAzhaController.text,
          )!,
      };
      if (submittedTimings.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter at least one prayer time.'),
          ),
        );
        setState(() => _submitting = false);
        return;
      }
      final invalidTimingMessage = _invalidSubmittedTimingMessage(
        submittedTimings,
      );
      if (invalidTimingMessage != null) {
        if (!mounted) return;
        await _showTimingValidationDialog(invalidTimingMessage);
        if (mounted) setState(() => _submitting = false);
        return;
      }

      final timingData = {
        if (_shareContributorDetails)
          'timing_verified_by_name': contributorName,
        'timing_verification_status': 'source_verified',
        'contributor_contact_shared': _shareContributorDetails,
        'verified_by_name_private': contributorName,
        'role': _role,
        'maslak': _maslak,
        'city': _cityController.text.trim(),
        'area': _areaController.text.trim(),
        'timing_updated_at': FieldValue.serverTimestamp(),
        if (_selectedMosque?.placeId != null)
          'place_id': _selectedMosque!.placeId!,
      };

      final city = _cityController.text.trim();
      // Use actual Firestore doc ID when updating existing mosque
      final resolvedDocId = (_mosqueMode == 'existing' &&
              _selectedMosque?.firestoreDocId != null)
          ? _selectedMosque!.firestoreDocId!
          : mosqueDocId(mosqueName, city, area: _areaController.text.trim());
      final mosqueRef = db.collection('mosques').doc(resolvedDocId);
      final existingMosqueSnap = await mosqueRef.get();
      final existingMosqueData = existingMosqueSnap.data();
      final shouldWriteAddedBy = !existingMosqueSnap.exists ||
          _readString(existingMosqueData?['added_by_name_private']) == null;
      final firstContributorData = {
        if (shouldWriteAddedBy) 'added_by_name': contributorName,
        if (shouldWriteAddedBy) 'added_by_name_private': contributorName,
        if (shouldWriteAddedBy)
          'added_by_uid': FirebaseAuth.instance.currentUser?.uid,
        if (shouldWriteAddedBy) 'added_at': FieldValue.serverTimestamp(),
      };
      final timingEditData = {
        for (final entry in submittedTimings.entries)
          'timing_edit_meta.${entry.key}': {
            'name': contributorName,
            'uid': FirebaseAuth.instance.currentUser?.uid,
            'value': entry.value,
            'updated_at': FieldValue.serverTimestamp(),
          },
      };
      if (_mosqueMode == 'existing' && _selectedMosque != null) {
        await mosqueRef.set({
          'name': mosqueName,
          'city': city,
          'address': _selectedMosque?.address ?? '',
          'latitude': _selectedMosque?.latitude,
          'longitude': _selectedMosque?.longitude,
          ...firstContributorData,
          ...timingData,
        }, SetOptions(merge: true));
        // Update individual timing fields to preserve other prayers
        await mosqueRef.update({
          for (final e in submittedTimings.entries) 'timings.${e.key}': e.value,
          ...timingEditData,
        });
      } else {
        await mosqueRef.set({
          'name': mosqueName,
          'city': city,
          'address': _addressController.text.trim(),
          ...firstContributorData,
          ...timingData,
        }, SetOptions(merge: true));
        await mosqueRef.update({
          for (final e in submittedTimings.entries) 'timings.${e.key}': e.value,
          ...timingEditData,
        });
      }

      if (contributorName.isNotEmpty && mounted) {
        await context.read<AppState>().setContributorName(contributorName);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('JazakAllah! $mosqueName timings saved. ✅')),
        );
        Navigator.of(context).pop();
      }

      // Score is awarded by Cloud Function (onContributionLogCreated).
      await db.collection('contribution_logs').add({
        'name': contributorName,
        'phone': verifiedPhone,
        'uid': FirebaseAuth.instance.currentUser?.uid,
        'city': _cityController.text.trim(),
        'mosque_name': mosqueName,
        'mode': _mosqueMode,
        'scoreAwarded': false,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      debugPrint('SUBMIT ERROR: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _invalidSubmittedTimingMessage(Map<String, String> timings) {
    final cityKey = _cityController.text.trim().toLowerCase();
    CityInfo? city;
    for (final candidate in indianCities) {
      if (candidate.name.toLowerCase() == cityKey) {
        city = candidate;
        break;
      }
    }
    final service = city == null
        ? IslamicTimingService()
        : IslamicTimingService(
            latitude: city.latitude,
            longitude: city.longitude,
          );
    final validator = PrayerTimeValidator(
      service: service,
      cityName: _cityController.text.trim(),
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

  String? _firebaseAuthPhone() {
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber;
    return phone == null ? null : PhoneUtils.normalize(phone);
  }
}

class _MosqueSelectorField extends StatelessWidget {
  const _MosqueSelectorField({
    required this.selectedMosque,
    required this.mosqueCount,
    required this.onTap,
  });

  final Mosque? selectedMosque;
  final int mosqueCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mosque = selectedMosque;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Select mosque from current listing',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.search),
        ),
        child: mosque == null
            ? Text(
                mosqueCount == 0
                    ? 'No mosque in current listing'
                    : 'Search $mosqueCount masjids',
                style: const TextStyle(color: Colors.black54),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mosque.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${mosque.area} - ${_mosqueDistanceLabel(mosque)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MosquePickerSheet extends StatefulWidget {
  const _MosquePickerSheet({
    required this.mosques,
    required this.selectedMosque,
    required this.cityName,
  });

  final List<Mosque> mosques;
  final Mosque? selectedMosque;
  final String cityName;

  @override
  State<_MosquePickerSheet> createState() => _MosquePickerSheetState();
}

class _MosquePickerSheetState extends State<_MosquePickerSheet> {
  final _search = TextEditingController();
  late List<Mosque> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.mosques;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _filtered = widget.mosques.where((mosque) {
        if (query.isEmpty) return true;
        return mosque.name.toLowerCase().contains(query) ||
            mosque.area.toLowerCase().contains(query) ||
            mosque.address.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText:
                      'Search ${widget.cityName} mosques, areas or landmarks',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: _onSearch,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_filtered.length} of ${widget.mosques.length} masjids',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('No mosque found.'))
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final mosque = _filtered[index];
                        final sel = widget.selectedMosque;
                        final selected = sel != null &&
                            ((mosque.placeId != null &&
                                    mosque.placeId == sel.placeId) ||
                                (mosque.name == sel.name &&
                                    mosque.area == sel.area));
                        return ListTile(
                          leading: Icon(
                            selected ? Icons.check_circle : Icons.mosque,
                            color: const Color(0xFF0F7C68),
                          ),
                          title: Text(
                            mosque.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  selected ? FontWeight.w900 : FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '${mosque.area} - ${_mosqueDistanceLabel(mosque)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).pop(mosque),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _OtpVerificationPanel extends StatelessWidget {
  const _OtpVerificationPanel({
    required this.phoneController,
    required this.otpController,
    required this.otpSent,
    required this.phoneVerified,
    required this.sendingOtp,
    required this.verifyingOtp,
    required this.statusMessage,
    required this.cooldownNotifier,
    required this.onSendOtp,
    required this.onVerifyOtp,
  });

  final TextEditingController phoneController;
  final TextEditingController otpController;
  final bool otpSent;
  final bool phoneVerified;
  final bool sendingOtp;
  final bool verifyingOtp;
  final String? statusMessage;
  final ValueListenable<int> cooldownNotifier;
  final VoidCallback onSendOtp;
  final VoidCallback onVerifyOtp;

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0F7C68);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7F3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                phoneVerified ? Icons.verified : Icons.sms,
                color: teal,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  phoneVerified ? 'Mobile verified' : 'OTP verification',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!otpSent || phoneVerified) ...[
            TextFormField(
              controller: phoneController,
              enabled: !phoneVerified,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '9876543210 or +447911123456',
                prefixIcon: Icon(Icons.phone, size: 18),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              validator: (value) => PhoneUtils.normalize(value ?? '') == null
                  ? 'Enter a 10-digit number or full international format'
                  : null,
            ),
            if (!phoneVerified) ...[
              const SizedBox(height: 10),
              ValueListenableBuilder<int>(
                valueListenable: cooldownNotifier,
                builder: (context, cooldown, _) {
                  return FilledButton(
                    onPressed: (sendingOtp || cooldown > 0) ? null : onSendOtp,
                    style: FilledButton.styleFrom(backgroundColor: teal),
                    child: sendingOtp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            cooldown > 0
                                ? 'Resend in ${cooldown}s'
                                : 'Send OTP',
                          ),
                  );
                },
              ),
            ],
          ] else ...[
            TextFormField(
              controller: otpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Enter OTP',
                prefixIcon: Icon(Icons.sms, size: 18),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: verifyingOtp ? null : onVerifyOtp,
              style: FilledButton.styleFrom(backgroundColor: teal),
              child: verifyingOtp
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
            ValueListenableBuilder<int>(
              valueListenable: cooldownNotifier,
              builder: (context, cooldown, _) {
                return TextButton(
                  onPressed: (sendingOtp || cooldown > 0) ? null : onSendOtp,
                  child: Text(
                    cooldown > 0 ? 'Resend in ${cooldown}s' : 'Resend OTP',
                  ),
                );
              },
            ),
          ],
          if (phoneVerified) ...[
            const SizedBox(height: 8),
            const Text(
              'Mobile verified',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: teal,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (statusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              statusMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: phoneVerified ? teal : Colors.black54,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimingInputGrid extends StatefulWidget {
  const _TimingInputGrid({
    required this.fajrController,
    required this.zoharController,
    required this.asrController,
    required this.maghribController,
    required this.ishaController,
    required this.jumaController,
  });

  final TextEditingController fajrController;
  final TextEditingController zoharController;
  final TextEditingController asrController;
  final TextEditingController maghribController;
  final TextEditingController ishaController;
  final TextEditingController jumaController;

  @override
  State<_TimingInputGrid> createState() => _TimingInputGridState();
}

class _TimingInputGridState extends State<_TimingInputGrid> {
  Future<void> _pick(
    BuildContext ctx,
    TextEditingController ctrl,
    String label,
  ) async {
    final p = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay.now(),
      helpText: label,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (p != null) {
      ctrl.text =
          '${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = [
      ('Fajr', 'fajr', widget.fajrController),
      ('Zuhr', 'zohar', widget.zoharController),
      ('Asr', 'asr', widget.asrController),
      ('Maghrib', 'maghrib', widget.maghribController),
      ('Isha', 'isha', widget.ishaController),
      ("Jumu'ah", 'juma', widget.jumaController),
    ];

    Widget cell(int i) {
      final field = fields[i];
      return Expanded(
        child: SizedBox(
          height: 76,
          child: InkWell(
            onTap: () => _pick(context, field.$3, field.$1),
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: field.$1,
                border: const OutlineInputBorder(),
                suffixIcon: const Icon(Icons.access_time),
              ),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: field.$3,
                builder: (context, value, _) => Text(
                  value.text.isEmpty
                      ? 'Tap to set'
                      : formatPrayerStoredTime(field.$2, value.text),
                  style: TextStyle(
                    color: value.text.isEmpty ? Colors.black38 : Colors.black87,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < fields.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(children: [cell(i), const SizedBox(width: 10), cell(i + 1)]),
        ],
      ],
    );
  }
}

class _HadithOrnament extends StatelessWidget {
  const _HadithOrnament({required this.flip});
  final bool flip;
  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleX: flip ? -1 : 1,
      child: const Text(
        '❧',
        style: TextStyle(color: Color(0xFFD4AF37), fontSize: 22),
      ),
    );
  }
}

class _RewardsPreviewCard extends StatelessWidget {
  const _RewardsPreviewCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFE4B4)),
        ),
        child: const Row(
          children: [
            Icon(Icons.workspace_premium, size: 16, color: Color(0xFFB8860B)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Contributors Leaderboard',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}
