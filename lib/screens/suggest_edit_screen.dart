import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mosque.dart';
import '../services/location_service.dart';

class SuggestEditScreen extends StatefulWidget {
  const SuggestEditScreen({super.key, required this.mosque});
  final Mosque mosque;
  @override
  State<SuggestEditScreen> createState() => _SuggestEditScreenState();
}

class _SuggestEditScreenState extends State<SuggestEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _fajrController = TextEditingController();
  final _zuhrController = TextEditingController();
  final _asrController = TextEditingController();
  final _maghribController = TextEditingController();
  final _ishaController = TextEditingController();
  final _jumaController = TextEditingController();
  bool _firebaseReady = false;
  bool _sendingOtp = false;
  bool _phoneVerified = false;
  bool _submitting = false;
  bool _otpSent = false;
  bool _capturingLocation = false;
  bool _isAtMosqueNow = false;
  String _issueType = 'location';
  String? _verificationId;
  String? _otpStatus;
  double? _capturedLat;
  double? _capturedLng;
  String? _capturedLocationText;

  @override
  void initState() {
    super.initState();
    _loadVerification();
  }

  Future<void> _loadVerification() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('verified_phone');
    final verifiedAt = prefs.getInt('verified_at') ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - verifiedAt;
    if (phone != null && age < 86400000) {
      if (mounted) setState(() {
        _phoneVerified = true;
        _phoneController.text = phone;
        _otpStatus = 'Mobile verified.';
      });
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _fajrController.dispose();
    _zuhrController.dispose();
    _asrController.dispose();
    _maghribController.dispose();
    _ishaController.dispose();
    _jumaController.dispose();
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
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => ctrl.text = _formatTimeOfDay(picked));
  }

  Future<void> _ensureFirebase() async {
    if (_firebaseReady) return;
    await Firebase.initializeApp();
    _firebaseReady = true;
  }

  Future<void> _sendOtp() async {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) { setState(() => _otpStatus = 'Enter valid mobile number.'); return; }
    setState(() { _sendingOtp = true; _otpStatus = 'Sending OTP...'; });
    try {
      await _ensureFirebase();
      final phone = digits.startsWith('91') && digits.length == 12 ? '+$digits' : '+91$digits';
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (cred) async {
          await FirebaseAuth.instance.signInWithCredential(cred);
          if (!mounted) return;
          setState(() { _phoneVerified = true; _otpStatus = 'Verified'; });
        },
        verificationFailed: (e) { if (!mounted) return; setState(() => _otpStatus = e.message ?? 'OTP failed.'); },
        codeSent: (id, _) { if (!mounted) return; setState(() { _verificationId = id; _otpSent = true; _otpStatus = 'OTP sent.'; }); },
        codeAutoRetrievalTimeout: (id) => _verificationId = id,
        timeout: const Duration(seconds: 60),
      );
    } catch (_) { setState(() => _otpStatus = 'OTP failed. Try again.'); }
    finally { if (mounted) setState(() => _sendingOtp = false); }
  }

  Future<void> _verifyOtp() async {
    if (_verificationId == null || _otpController.text.trim().isEmpty) return;
    try {
      final cred = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: _otpController.text.trim());
      await FirebaseAuth.instance.signInWithCredential(cred);
      if (!mounted) return;
      setState(() { _phoneVerified = true; _otpStatus = 'Mobile verified.'; });
    } catch (_) { setState(() => _otpStatus = 'Invalid OTP.'); }
  }

  Future<void> _captureCurrentLocation() async {
    setState(() => _capturingLocation = true);
    final location = await LocationService().currentOrFallback();
    if (!mounted) return;
    if (!location.isCurrentLocation) {
      setState(() => _capturingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GPS unavailable.')));
      return;
    }
    setState(() {
      _capturedLat = location.latitude;
      _capturedLng = location.longitude;
      _capturedLocationText = '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
      _capturingLocation = false;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_phoneVerified) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verify mobile number first.'))); return; }
    if ((_issueType == 'timing' || _issueType == 'both') && _fajrController.text.trim().isEmpty && _zuhrController.text.trim().isEmpty && _asrController.text.trim().isEmpty && _maghribController.text.trim().isEmpty && _ishaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kam az kam ek namaz ka waqt zaroor chunein.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await _ensureFirebase();
      final data = <String, dynamic>{
        'mosque_name': widget.mosque.name, 'city': widget.mosque.city, 'area': widget.mosque.area,
        'edit_type': 'timing_or_location', 'issue_type': _issueType, 'is_at_mosque_now': _isAtMosqueNow,
        if (_capturedLat != null) 'captured_latitude': _capturedLat,
        if (_capturedLng != null) 'captured_longitude': _capturedLng,
        'suggested_by_phone': _phoneController.text.trim(), 'status': 'submitted', 'created_at': FieldValue.serverTimestamp(),
      };
      if (_issueType == 'timing' || _issueType == 'both') {
        if (_fajrController.text.trim().isNotEmpty) data['fajr'] = _fajrController.text.trim();
        if (_zuhrController.text.trim().isNotEmpty) data['zohar'] = _zuhrController.text.trim();
        if (_asrController.text.trim().isNotEmpty) data['asr'] = _asrController.text.trim();
        if (_maghribController.text.trim().isNotEmpty) data['maghrib'] = _maghribController.text.trim();
        if (_ishaController.text.trim().isNotEmpty) data['isha'] = _ishaController.text.trim();
        if (_jumaController.text.trim().isNotEmpty) data['juma'] = _jumaController.text.trim();
      }
      await FirebaseFirestore.instance.collection('mosque_edits').add(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JazakAllah Khair! Request submit ho gayi.')));
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not submit. Check internet.')));
    } finally { if (mounted) setState(() => _submitting = false); }
  }

  Widget _timeField(TextEditingController ctrl, String label) {
    return TextFormField(
      controller: ctrl,
      readOnly: true,
      onTap: () => _pickTime(ctrl, label),
      decoration: InputDecoration(
        labelText: label, hintText: '--:--',
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.access_time, size: 18),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suggest an edit')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.mosque.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(widget.mosque.area, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _issueType,
                decoration: const InputDecoration(labelText: 'Kis cheez mein madad chahiye?', border: OutlineInputBorder()),
                items: const [
                  
                  DropdownMenuItem(value: 'location', child: Text('Masjid location update')),
                  
                ],
                onChanged: (value) => setState(() => _issueType = value ?? _issueType),
              ),
              if (_issueType == 'timing' || _issueType == 'both') ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFF1F8E9), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF81C784))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [Icon(Icons.access_time, color: Color(0xFF2E7D32), size: 18), SizedBox(width: 6), Text('Namaz Timings', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)))]),
                      const SizedBox(height: 4),
                      const Text('Tap karein — clock se waqt chunein', style: TextStyle(fontSize: 11, color: Colors.black54)),
                      const SizedBox(height: 12),
                      Row(children: [Expanded(child: _timeField(_fajrController, 'Fajr')), const SizedBox(width: 8), Expanded(child: _timeField(_zuhrController, 'Zuhr')), const SizedBox(width: 8), Expanded(child: _timeField(_asrController, 'Asr'))]),
                      const SizedBox(height: 8),
                      Row(children: [Expanded(child: _timeField(_maghribController, 'Maghrib')), const SizedBox(width: 8), Expanded(child: _timeField(_ishaController, 'Isha')), const SizedBox(width: 8), Expanded(child: _timeField(_jumaController, 'Juma'))]),
                    ],
                  ),
                ),
              ],
              if (_issueType == 'location' || _issueType == 'both') ...[
                const SizedBox(height: 12),
                CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Main abhi masjid par hoon'), subtitle: const Text('Tick karne ke baad location capture kar sakte hain.'), value: _isAtMosqueNow, onChanged: (value) => setState(() => _isAtMosqueNow = value ?? false)),
                if (_isAtMosqueNow) Align(alignment: Alignment.centerLeft, child: FilledButton.tonalIcon(onPressed: _capturingLocation ? null : _captureCurrentLocation, icon: const Icon(Icons.my_location), label: Text(_capturingLocation ? 'Location le rahe...' : 'Capture location'))),
                if (_capturedLocationText != null) ...[const SizedBox(height: 6), Text('Captured: $_capturedLocationText', style: const TextStyle(color: Color(0xFF0F7C68), fontSize: 12))],
              ],
              const SizedBox(height: 16),
              TextFormField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Your mobile number', prefixText: '+91 ', border: OutlineInputBorder()), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFEAF7F3), borderRadius: BorderRadius.circular(8)),
                child: Column(children: [
                  Row(children: [
                    Icon(_phoneVerified ? Icons.verified : Icons.sms, color: const Color(0xFF0F7C68)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_phoneVerified ? 'Mobile verified' : 'OTP verification', style: const TextStyle(fontWeight: FontWeight.w800))),
                    FilledButton(onPressed: _sendingOtp || _phoneVerified ? null : _sendOtp, child: Text(_sendingOtp ? 'Sending...' : _otpSent ? 'Resend' : 'Send OTP')),
                  ]),
                  if (_otpSent && !_phoneVerified) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: TextFormField(controller: _otpController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'OTP', border: OutlineInputBorder()))),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _verifyOtp, child: const Text('Verify')),
                    ]),
                  ],
                  if (_otpStatus != null) ...[const SizedBox(height: 8), Text(_otpStatus!, style: TextStyle(color: _phoneVerified ? const Color(0xFF0F7C68) : Colors.black54, fontSize: 12))],
                ]),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(onPressed: _submitting ? null : _submit, icon: const Icon(Icons.send), label: Text(_submitting ? 'Submitting...' : 'Submit')),
            ],
          ),
        ),
      ),
    );
  }
}
