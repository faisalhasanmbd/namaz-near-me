import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_provider.dart';
import '../services/otp_session.dart';
import '../utils/phone_utils.dart';
import '../utils/mosque_utils.dart';

// ── Private helpers (also present in contributor_signup_screen.dart where used)

int _readContributorInt(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
  }
  return 0;
}

String _cleanContributorName(Object? value) {
  return _cleanContributorNameOrNull(value) ?? 'Namaz Volunteer';
}

String? _cleanContributorNameOrNull(Object? value) {
  final name = value?.toString().trim() ?? '';
  if (name.isEmpty || name.toLowerCase() == 'namaz volunteer') return null;
  return name;
}

const _namazAndroidAppUrl =
    'https://play.google.com/store/apps/details?id=com.food4u.namaznearme';
const _namazIosAppUrl =
    'https://apps.apple.com/us/app/namaz-near-me/id6773680872';

class _RewardTier {
  const _RewardTier({
    required this.name,
    required this.threshold,
    required this.discountPercent,
    required this.description,
  });

  final String name;
  final int threshold;
  final int discountPercent;
  final String description;
}

const _rewardTiers = [
  _RewardTier(
    name: 'Bronze',
    threshold: 0,
    discountPercent: 0,
    description: 'Unlocked on first verified login.',
  ),
  _RewardTier(
    name: 'Silver',
    threshold: 5,
    discountPercent: 0,
    description: 'Unlocked after 5 prayer timing updates.',
  ),
  _RewardTier(
    name: 'Gold',
    threshold: 10,
    discountPercent: 5,
    description: 'Unlocked after 10 prayer timing updates.',
  ),
  _RewardTier(
    name: 'Diamond',
    threshold: 100,
    discountPercent: 10,
    description: 'Unlocked after 100 prayer timing updates.',
  ),
  _RewardTier(
    name: 'Ambassador',
    threshold: 1000,
    discountPercent: 20,
    description: 'Unlocked after 1000 prayer timing updates.',
  ),
];

_RewardTier _rewardTierForScore(int score) {
  return _rewardTiers.lastWhere((tier) => score >= tier.threshold);
}

_RewardTier? _nextRewardTierForScore(int score) {
  for (final tier in _rewardTiers) {
    if (score < tier.threshold) return tier;
  }
  return null;
}

// ignore: unused_element
int _starCountForReward({
  required int score,
  required int masjidCount,
  required int locationUpdateCount,
}) {
  var stars = 1; // Bronze: first verified login.
  if (locationUpdateCount > 0 || score >= 5) stars++;
  if (masjidCount > 0 || score >= 10) stars++;
  if (score >= 100) stars++;
  if (score >= 1000) stars++;
  return stars;
}

// Also used in contributor_signup_screen.dart — kept in sync.
// ignore: unused_element
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

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({
    super.key,
    required this.cityName,
    required this.onBackfill,
  });

  final String cityName;
  final Future<void> Function() onBackfill;

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  static const _targetScore = 1000;
  final _certificateKey = GlobalKey();
  var _sharingCertificate = false;
  int _leaderboardTab = 0;

  @override
  void initState() {
    super.initState();
    widget.onBackfill().ignore();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contributor Rewards')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        physics: const ClampingScrollPhysics(),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0A5244), Color(0xFF083D32)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD4AF37), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                children: [
                  // Corner ornaments + bismillah
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _HadithOrnament(flip: false),
                      Text(
                        'بِسْمِ ٱللَّهِ',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: Color(0xFFD4AF37),
                          fontSize: 10,
                        ),
                      ),
                      _HadithOrnament(flip: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Arabic — one line each, compact
                  const Text(
                    'مَنْ دَلَّ عَلَى خَيْرٍ',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.5,
                    ),
                  ),
                  const Text(
                    'فَلَهُ مِثْلُ أَجْرِ فَاعِلِهِ',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Separator
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.4),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '☽ ✦ ☾',
                          style: TextStyle(
                            color: Color(0xFFD4AF37),
                            fontSize: 11,
                            letterSpacing: 3,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // English
                  const Text(
                    '"One who guides others to something good has a reward equal to that of its doer."',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Attribution compact
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Column(
                      children: [
                        Text(
                          'Narrated by Abu Mas\'ud al-Ansari ؓ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Companion of Muhammad ﷺ (Peace be upon him)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 10.5,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Sahih Muslim 1893a  ·  Book 33, Hadith 195  ·  USC-MSA: Book 20, Hadith 4665',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFD4AF37),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const _RewardRulesCard(),
          const SizedBox(height: 18),
          // Certificate always at top — visible without scrolling leaderboard
          _CertificateSection(
            cityName: widget.cityName,
            sharingCertificate: _sharingCertificate,
            onPreviewCertificate: _openCertificatePreview,
            onShareWhatsApp: _shareCertificateText,
          ),
          const SizedBox(height: 18),
          const _RewardsSectionTitle('Leaderboard'),
          const SizedBox(height: 8),
          _buildLeaderboardTabBar(),
          const SizedBox(height: 12),
          _buildLeaderboardContent(),
          const SizedBox(height: 18),
          _MyProgressSection(
            cityName: widget.cityName,
            targetScore: _targetScore,
            sharingCertificate: _sharingCertificate,
            onPreviewCertificate: _openCertificatePreview,
            onShareWhatsApp: _shareCertificateText,
            onCopyLink: _copyAppLink,
            onOpenAppLink: _openAppLink,
          ),
        ],
      ),
    );
  }

  String _certificateShareText(String name) {
    return 'Jazakallah Khair to $name for helping keep masjid namaz timings accurate on Namaz Near Me.\n\nThese efforts are for the Hereafter; may Allah also place benefit in them in this world.\n\nDownload Namaz Near Me:\n$_namazAndroidAppUrl';
  }

  Future<void> _shareCertificate(String name) async {
    if (_sharingCertificate) return;
    setState(() => _sharingCertificate = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final boundary = _certificateKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('Certificate is not ready yet.');
      }
      final image = await boundary.toImage(pixelRatio: 4);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null) {
        throw StateError('Could not render certificate.');
      }
      final directory = await getTemporaryDirectory();
      final safeName = name
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final file = File(
        '${directory.path}/namaz-near-me-certificate-${safeName.isEmpty ? 'contributor' : safeName}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          title: 'Namaz Near Me Volunteer Appreciation',
          subject: 'Namaz Near Me Volunteer Appreciation',
          text: _certificateShareText(name),
          files: [
            XFile(
              file.path,
              mimeType: 'image/png',
              name: 'namaz-near-me-volunteer-certificate.png',
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Certificate share failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _sharingCertificate = false);
    }
  }

  Future<void> _shareCertificateText(String name) async {
    await SharePlus.instance.share(
      ShareParams(title: 'Namaz Near Me', text: _certificateShareText(name)),
    );
  }

  Future<Uint8List?> _renderCertificateBytes() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final boundary = _certificateKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 4);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _downloadCertificateToGallery(String name) async {
    if (_sharingCertificate) return;
    setState(() => _sharingCertificate = true);
    try {
      final bytes = await _renderCertificateBytes();
      if (bytes == null) throw StateError('Could not render certificate.');
      final directory = await getTemporaryDirectory();
      final safeName = name
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final file = File(
        '${directory.path}/certificate-${safeName.isEmpty ? 'contributor' : safeName}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Gal.putImage(file.path, album: 'Namaz Near Me');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Certificate saved to Gallery! Set as WhatsApp Status.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _sharingCertificate = false);
    }
  }

  Future<void> _copyAppLink() async {
    await Clipboard.setData(const ClipboardData(text: _namazAndroidAppUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('App download link copied.')));
  }

  Future<void> _openAppLink() async {
    await launchUrl(
      Uri.parse(_namazAndroidAppUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openCertificatePreview(
    String name,
    int score,
    int masjidCount,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: .82,
            minChildSize: .55,
            maxChildSize: .95,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF6FBF9),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCCD8D5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Certificate Preview',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    RepaintBoundary(
                      key: _certificateKey,
                      child: _ShareableCertificate(
                        name: name,
                        score: score,
                        masjidCount: masjidCount,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Download to Gallery (for WhatsApp Status)
                    FilledButton.icon(
                      onPressed: _sharingCertificate
                          ? null
                          : () => _downloadCertificateToGallery(name),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Save to Gallery (WhatsApp Status)'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F7C68),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Share image + text
                    FilledButton.icon(
                      onPressed: _sharingCertificate
                          ? null
                          : () => _shareCertificate(name),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share Certificate'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF128E78),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _shareCertificateText(name),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Share WhatsApp Text'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildLeaderboardTabBar() {
    const labels = ['City', 'State', 'Country', 'World'];
    const teal = Color(0xFF0F7C68);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            ChoiceChip(
              label: Text(labels[i]),
              selected: _leaderboardTab == i,
              onSelected: (_) => setState(() => _leaderboardTab = i),
              selectedColor: teal,
              labelStyle: TextStyle(
                color: _leaderboardTab == i
                    ? Colors.white
                    : const Color(0xFF3F444A),
                fontWeight: FontWeight.w700,
              ),
              shape: const StadiumBorder(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLeaderboardContent() {
    return switch (_leaderboardTab) {
      0 => _CityLeaderboard(cityName: widget.cityName),
      1 => const _ComingSoonLeaderboard(scope: 'State'),
      2 => const _ComingSoonLeaderboard(scope: 'Country'),
      _ => const _WorldLeaderboard(),
    };
  }
}

// Certificate card shown at the top of rewards — always visible
class _CertificateSection extends StatefulWidget {
  const _CertificateSection({
    required this.cityName,
    required this.sharingCertificate,
    required this.onPreviewCertificate,
    required this.onShareWhatsApp,
  });

  final String cityName;
  final bool sharingCertificate;
  final Future<void> Function(String, int, int) onPreviewCertificate;
  final Future<void> Function(String) onShareWhatsApp;

  @override
  State<_CertificateSection> createState() => _CertificateSectionState();
}

class _CertificateSectionState extends State<_CertificateSection> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, authSnap) {
        final uid = authSnap.data?.uid;

        // Logged-in: certificate is shown inside "Your Progress" section below.
        if (uid != null) return const SizedBox.shrink();

        // Not logged in: compact inline OTP login
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _RewardsSectionTitle('Certificate'),
            const _CertificateLoginBox(),
          ],
        );
      },
    );
  }
}

class _CertificateLoginBox extends StatefulWidget {
  const _CertificateLoginBox();
  @override
  State<_CertificateLoginBox> createState() => _CertificateLoginBoxState();
}

class _CertificateLoginBoxState extends State<_CertificateLoginBox> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String? _verificationId;
  bool _otpSent = false;
  bool _loading = false;
  String? _status;
  int _otpCooldownSeconds = 0;
  Timer? _otpCooldownTimer;

  void _startOtpCooldown() {
    _otpCooldownTimer?.cancel();
    setState(() => _otpCooldownSeconds = 60);
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

  Future<void> _markPhoneVerified(String phone) async {
    final normalized = PhoneUtils.normalize(phone) ?? phone;
    await OtpSession.saveVerifiedPhone(normalized);
    if (!mounted) return;
    await context.read<AppState>().markPhoneVerified(normalized);
    setState(() => _status = 'Mobile verified.');
  }

  @override
  void dispose() {
    _otpCooldownTimer?.cancel();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_otpCooldownSeconds > 0) return;
    final phone = PhoneUtils.normalize(_phoneCtrl.text);
    if (phone == null) {
      setState(() => _status = 'Enter a valid mobile number.');
      return;
    }
    setState(() {
      _loading = true;
      _status = 'Sending OTP...';
    });
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (cred) async {
          await FirebaseAuth.instance.signInWithCredential(cred);
          await _markPhoneVerified(phone);
        },
        verificationFailed: (e) {
          if (mounted) setState(() => _status = e.message ?? 'OTP failed.');
        },
        codeSent: (id, _) {
          if (!mounted) return;
          setState(() {
            _verificationId = id;
            _otpSent = true;
            _status = 'OTP sent. Enter the 6-digit code.';
          });
          _startOtpCooldown();
        },
        codeAutoRetrievalTimeout: (id) {
          if (!mounted) return;
          setState(() {
            _verificationId = id;
            _status = 'OTP expired. Tap Resend.';
          });
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (_) {
      if (mounted) setState(() => _status = 'Failed. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_verificationId == null || _otpCtrl.text.trim().isEmpty) {
      setState(() => _status = 'Enter the OTP code.');
      return;
    }
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpCtrl.text.trim(),
      );
      final result = await FirebaseAuth.instance.signInWithCredential(cred);
      final phone = result.user?.phoneNumber ?? '';
      if (phone.isNotEmpty) await _markPhoneVerified(phone);
    } catch (_) {
      if (mounted) setState(() => _status = 'Invalid OTP. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0F7C68);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded, color: teal, size: 28),
          const SizedBox(height: 8),
          const Text('Login to view your certificate',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF222222))),
          const SizedBox(height: 14),
          if (!_otpSent) ...[
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: 'Mobile number (+91...)',
                prefixIcon: Icon(Icons.phone, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    (_loading || _otpCooldownSeconds > 0) ? null : _sendOtp,
                style: FilledButton.styleFrom(
                  backgroundColor: teal,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        _otpCooldownSeconds > 0
                            ? 'Resend in ${_otpCooldownSeconds}s'
                            : 'Send OTP',
                        style: const TextStyle(fontSize: 13),
                      ),
              ),
            ),
          ] else ...[
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '6-digit OTP',
                prefixIcon: Icon(Icons.sms, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _verifyOtp,
                style: FilledButton.styleFrom(
                  backgroundColor: teal,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Verify', style: TextStyle(fontSize: 13)),
              ),
            ),
            TextButton(
              onPressed:
                  (_loading || _otpCooldownSeconds > 0) ? null : _sendOtp,
              child: Text(
                _otpCooldownSeconds > 0
                    ? 'Resend in ${_otpCooldownSeconds}s'
                    : 'Resend OTP',
              ),
            ),
          ],
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(_status!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    color: _status!.contains('sent')
                        ? teal
                        : Colors.red.shade700)),
          ],
        ],
      ),
    );
  }
}

class _CertificateCard extends StatelessWidget {
  const _CertificateCard({
    required this.name,
    required this.score,
    required this.isSharing,
    required this.onPreview,
    required this.onWhatsApp,
  });

  final String name;
  final int score;
  final bool isSharing;
  final VoidCallback onPreview;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _RewardsSectionTitle('Certificate'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8ECEF)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F6EF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.workspace_premium,
                      color: Color(0xFF0F7C68),
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Appreciation Certificate',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          name.isNotEmpty
                              ? '$name · $score updates'
                              : 'Preview your certificate',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF657078),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isSharing ? null : onPreview,
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('Preview & Share Certificate'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F7C68),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onWhatsApp,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Share via WhatsApp'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyRewardsState extends StatelessWidget {
  const _EmptyRewardsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFAF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6EEE8)),
      ),
      child: const Column(
        children: [
          Icon(Icons.workspace_premium, color: Color(0xFF0F7C68), size: 42),
          SizedBox(height: 10),
          Text(
            'No contributors yet.',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 6),
          Text(
            'Approved timing updates will appear here as community rewards.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Leaderboard tab content widgets ──────────────────────────────────────

class _CityLeaderboard extends StatelessWidget {
  const _CityLeaderboard({required this.cityName});
  final String cityName;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('top_contributors')
          .where('city', isEqualTo: cityName)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[
          ...?snapshot.data?.docs,
        ]..sort((a, b) => _readContributorInt(b.data(), ['score'])
            .compareTo(_readContributorInt(a.data(), ['score'])));
        return _LeaderboardList(docs: docs.take(10).toList());
      },
    );
  }
}

class _WorldLeaderboard extends StatelessWidget {
  const _WorldLeaderboard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('top_contributors')
          .orderBy('score', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return _LeaderboardList(docs: docs);
      },
    );
  }
}

class _ComingSoonLeaderboard extends StatelessWidget {
  const _ComingSoonLeaderboard({required this.scope});
  final String scope;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        children: [
          const Icon(Icons.public_outlined, size: 36, color: Color(0xFF0F7C68)),
          const SizedBox(height: 8),
          Text(
            '$scope Leaderboard',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text('Coming soon', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  const _LeaderboardList({required this.docs});
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) return const _EmptyRewardsState();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ContributorHeroCard(
          name: _cleanContributorName(docs.first.data()['name']),
          score: _readContributorInt(docs.first.data(), ['score']),
          masjidCount: _readContributorInt(
              docs.first.data(), ['masjids', 'masjidCount', 'mosques']),
          locationUpdateCount: _readContributorInt(
              docs.first.data(), ['location_updates', 'locationUpdates']),
          rank: 1,
          city: (docs.first.data()['city'] as String? ?? '').trim(),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < docs.length; i++)
          _LeaderboardTile(
            rank: i + 1,
            name: _cleanContributorName(docs[i].data()['name']),
            score: _readContributorInt(docs[i].data(), ['score']),
            masjidCount: _readContributorInt(
                docs[i].data(), ['masjids', 'masjidCount', 'mosques']),
            locationUpdateCount: _readContributorInt(
                docs[i].data(), ['location_updates', 'locationUpdates']),
          ),
      ],
    );
  }
}

class _RewardsSectionTitle extends StatelessWidget {
  const _RewardsSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF555A60),
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: .3,
        ),
      ),
    );
  }
}

class _RewardRulesCard extends StatelessWidget {
  const _RewardRulesCard();

  @override
  Widget build(BuildContext context) {
    const levels = [
      ('🥉', 'Bronze', 'Login'),
      ('🕌', 'Gold Star', 'Add masjid'),
      ('⭐', 'Silver', '5 updates'),
      ('📍', 'Silver Star', 'Location'),
      ('🏅', 'Gold', '10 updates'),
      ('💎', 'Diamond', '100 updates'),
      ('🤝', 'Ambassador', '1000 updates'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RewardsSectionTitle('Reward Levels'),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < levels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  SizedBox(
                    width: 72,
                    height: 82,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5FBF9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFD6EDE8)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            levels[i].$1,
                            style: const TextStyle(fontSize: 24),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            levels[i].$2,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F5C4C),
                            ),
                          ),
                          Text(
                            levels[i].$3,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xFF7A7F85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContributorHeroCard extends StatelessWidget {
  const _ContributorHeroCard({
    required this.name,
    required this.score,
    required this.masjidCount,
    required this.locationUpdateCount,
    required this.rank,
    this.city = '',
  });

  final String name;
  final int score;
  final int masjidCount;
  final int locationUpdateCount;
  final int rank;
  final String city;

  @override
  Widget build(BuildContext context) {
    final tier = _rewardTierForScore(score);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F7C68), Color(0xFF128E78)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F7C68).withValues(alpha: .18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            city.isNotEmpty
                ? '${tier.name} Contributor · $city'
                : '${tier.name} Contributor',
            style: const TextStyle(
              color: Color(0xCCEFFFFB),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroStat(value: '$score', label: 'Updates'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroStat(
                  value: masjidCount == 0 ? '—' : '$masjidCount',
                  label: 'Masjids',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroStat(
                  value:
                      locationUpdateCount == 0 ? '—' : '$locationUpdateCount',
                  label: 'Locations',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroStat(value: '#$rank', label: 'Rank'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name, required this.radius});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFBDEEE4).withValues(alpha: .42),
      child: Text(
        initials.isEmpty ? 'NN' : initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xDDEFFFFB),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _MyProgressSection extends StatelessWidget {
  const _MyProgressSection({
    required this.cityName,
    required this.targetScore,
    required this.sharingCertificate,
    required this.onPreviewCertificate,
    required this.onShareWhatsApp,
    required this.onCopyLink,
    required this.onOpenAppLink,
  });

  final String cityName;
  final int targetScore;
  final bool sharingCertificate;
  final Future<void> Function(String, int, int) onPreviewCertificate;
  final Future<void> Function(String) onShareWhatsApp;
  final Future<void> Function() onCopyLink;
  final Future<void> Function() onOpenAppLink;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Verify your mobile number to track your progress.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('top_contributors')
          .doc(cityContributorDocId(cityName, uid))
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final myScore = data != null ? _readContributorInt(data, ['score']) : 0;
        final myMasjidCount = data != null
            ? _readContributorInt(data, ['masjids', 'masjidCount', 'mosques'])
            : 0;
        final myLocationUpdateCount = data != null
            ? _readContributorInt(data, [
                'location_updates',
                'locationUpdates',
              ])
            : 0;
        final myName = data != null ? _cleanContributorName(data['name']) : '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _RewardsSectionTitle('Your Progress'),
            _ProgressRewardCard(score: myScore, target: targetScore),
            const SizedBox(height: 16),
            const _RewardsSectionTitle('Achievements'),
            _AchievementsGrid(
              score: myScore,
              masjidCount: myMasjidCount,
              locationUpdateCount: myLocationUpdateCount,
            ),
            const SizedBox(height: 16),
            _CertificateTemplateCard(
              name: myName,
              score: myScore,
              masjidCount: myMasjidCount,
              isSharing: sharingCertificate,
              onPreviewCertificate: () =>
                  onPreviewCertificate(myName, myScore, myMasjidCount),
              onShareWhatsApp: () => onShareWhatsApp(myName),
              onCopyLink: onCopyLink,
              onOpenAppLink: onOpenAppLink,
            ),
          ],
        );
      },
    );
  }
}

class _ProgressRewardCard extends StatelessWidget {
  const _ProgressRewardCard({required this.score, required this.target});

  final int score;
  final int target;

  @override
  Widget build(BuildContext context) {
    final currentTier = _rewardTierForScore(score);
    final nextTier = _nextRewardTierForScore(score);
    final targetScore = nextTier?.threshold ?? target;
    final lowerScore = currentTier.threshold;
    final span = (targetScore - lowerScore).clamp(1, target);
    final progress =
        nextTier == null ? 1.0 : ((score - lowerScore) / span).clamp(0.0, 1.0);
    final remaining = nextTier == null ? 0 : targetScore - score;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECEF)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE9A8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${currentTier.name} Contributor',
                  style: const TextStyle(
                    color: Color(0xFF80620A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  nextTier == null
                      ? 'Ambassador unlocked'
                      : '${nextTier.name} at ${nextTier.threshold} ↗',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7A7F85),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              color: const Color(0xFF0F7C68),
              backgroundColor: const Color(0xFFE8ECEF),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$score prayer updates',
                style: const TextStyle(
                  color: Color(0xFF8A8F95),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                nextTier == null
                    ? 'Ambassador unlocked 🤝'
                    : '$remaining needed for ${nextTier.name}',
                style: const TextStyle(
                  color: Color(0xFF8A8F95),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AchievementsGrid extends StatelessWidget {
  const _AchievementsGrid({
    required this.score,
    required this.masjidCount,
    required this.locationUpdateCount,
  });

  final int score;
  final int masjidCount;
  final int locationUpdateCount;

  @override
  Widget build(BuildContext context) {
    final items = <_AchievementData>[
      const _AchievementData(
        icon: '🥉',
        title: 'Bronze',
        subtitle: 'First verified login',
        completed: true,
      ),
      _AchievementData(
        icon: '🕌',
        title: 'Gold Star',
        subtitle: masjidCount > 0 ? 'Masjid added' : 'Add a new masjid',
        completed: masjidCount > 0,
      ),
      _AchievementData(
        icon: '⭐',
        title: 'Silver',
        subtitle: score >= 5 ? '5 prayers completed' : '${5 - score} left',
        completed: score >= 5,
      ),
      _AchievementData(
        icon: '📍',
        title: 'Silver Star',
        subtitle: locationUpdateCount > 0
            ? 'Location updated'
            : 'Update a masjid location',
        completed: locationUpdateCount > 0,
      ),
      _AchievementData(
        icon: '🏅',
        title: 'Gold',
        subtitle: score >= 10 ? 'Unlocked' : '${10 - score} left',
        completed: score >= 10,
      ),
      _AchievementData(
        icon: '💎',
        title: 'Diamond',
        subtitle: score >= 100 ? 'Unlocked' : '${100 - score} left',
        completed: score >= 100,
      ),
      _AchievementData(
        icon: '🤝',
        title: 'Ambassador',
        subtitle:
            score >= 1000 ? 'Printed certificate' : '${1000 - score} left',
        completed: score >= 1000,
      ),
    ];

    // Build rows of 2; if total is odd, last item spans full width.
    const tileHeight = 66.0;
    const gap = 8.0;
    final rows = <Widget>[];
    for (int i = 0; i < items.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: gap));
      if (i + 1 < items.length) {
        rows.add(Row(
          children: [
            Expanded(
              child: SizedBox(
                  height: tileHeight, child: _AchievementTile(items[i])),
            ),
            const SizedBox(width: gap),
            Expanded(
              child: SizedBox(
                  height: tileHeight, child: _AchievementTile(items[i + 1])),
            ),
          ],
        ));
      } else {
        // Last item alone — full width, content centered
        rows.add(SizedBox(
            height: tileHeight,
            child: _AchievementTile(items[i], centered: true)));
      }
    }
    return Column(children: rows);
  }
}

class _AchievementData {
  const _AchievementData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.completed,
  });

  final String icon;
  final String title;
  final String subtitle;
  final bool completed;
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile(this.data, {this.centered = false});

  final _AchievementData data;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final textCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          data.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: data.completed
                ? const Color(0xFF0F7C68)
                : const Color(0xFF3F444A),
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          data.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF7A7F85),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: data.completed ? const Color(0xFFE0F6EF) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: data.completed
              ? const Color(0xFF6FCBBB)
              : const Color(0xFFE8ECEF),
        ),
      ),
      child: Row(
        mainAxisAlignment:
            centered ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Text(data.icon, style: const TextStyle(fontSize: 21)),
          const SizedBox(width: 9),
          if (centered) textCol else Expanded(child: textCol),
        ],
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  const _LeaderboardTile({
    required this.rank,
    required this.name,
    required this.score,
    required this.masjidCount,
    required this.locationUpdateCount,
  });

  final int rank;
  final String name;
  final int score;
  final int masjidCount;
  final int locationUpdateCount;

  @override
  Widget build(BuildContext context) {
    final tier = _rewardTierForScore(score);
    final rankColor = switch (rank) {
      1 => const Color(0xFFD99A00),
      2 => const Color(0xFF8A8F95),
      3 => const Color(0xFFC56F32),
      _ => const Color(0xFF0F7C68),
    };
    final tierEmoji = switch (tier.name) {
      'Bronze' => '🥉',
      'Silver' => '⭐',
      'Gold' => '🏅',
      'Diamond' => '💎',
      'Ambassador' => '🤝',
      _ => '🥉',
    };
    final tierColor = switch (tier.name) {
      'Bronze' => const Color(0xFFCD7F32),
      'Silver' => const Color(0xFF8A8F95),
      'Gold' => const Color(0xFFD4AF37),
      'Diamond' => const Color(0xFF42A5F5),
      'Ambassador' => const Color(0xFF0F7C68),
      _ => const Color(0xFFCD7F32),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECEF)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: rankColor,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _StatChip(label: '$score', sublabel: 'updates'),
                    const SizedBox(width: 6),
                    if (masjidCount > 0)
                      _StatChip(label: '$masjidCount', sublabel: 'mosques'),
                    if (masjidCount > 0) const SizedBox(width: 6),
                    if (locationUpdateCount > 0)
                      _StatChip(
                        label: '$locationUpdateCount',
                        sublabel: 'locations',
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$score pts',
                style: const TextStyle(
                  color: Color(0xFF0F7C68),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              Text(
                tierEmoji,
                style: TextStyle(fontSize: 18, color: tierColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.sublabel});
  final String label;
  final String sublabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F5C4C),
              ),
            ),
            TextSpan(
              text: sublabel,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF7A7F85),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CertificateTemplateCard extends StatelessWidget {
  const _CertificateTemplateCard({
    required this.name,
    required this.score,
    required this.masjidCount,
    required this.isSharing,
    required this.onPreviewCertificate,
    required this.onShareWhatsApp,
    required this.onCopyLink,
    required this.onOpenAppLink,
  });

  final String name;
  final int score;
  final int masjidCount;
  final bool isSharing;
  final VoidCallback onPreviewCertificate;
  final VoidCallback onShareWhatsApp;
  final VoidCallback onCopyLink;
  final VoidCallback onOpenAppLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _RewardsSectionTitle('Certificate'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8ECEF)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F6EF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.workspace_premium,
                      color: Color(0xFF0F7C68),
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Volunteer & Ambassador Rewards',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '$name · $score updates',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF657078),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isSharing ? null : onPreviewCertificate,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Preview & Share Certificate'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F7C68),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onShareWhatsApp,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onOpenAppLink,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('App Link'),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: onCopyLink,
                icon: const Icon(Icons.link),
                label: const Text('Copy Android download link'),
              ),
              const Text(
                'Digital certificate can be shared anytime. Printed Ambassador certificate unlocks at 1000 prayer timing updates.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF7A7F85), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShareableCertificate extends StatelessWidget {
  const _ShareableCertificate({
    required this.name,
    required this.score,
    required this.masjidCount,
  });

  final String name;
  final int score;
  final int masjidCount;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dateLabel = '${today.day} ${_monthName(today.month)} ${today.year}';
    return AspectRatio(
      aspectRatio: 1.24,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 620,
          height: 500,
          child: _CertificateCanvas(
            name: name,
            score: score,
            masjidCount: masjidCount,
            dateLabel: dateLabel,
          ),
        ),
      ),
    );
  }

  static String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }
}

class _CertificateCanvas extends StatelessWidget {
  const _CertificateCanvas({
    required this.name,
    required this.score,
    required this.masjidCount,
    required this.dateLabel,
  });

  final String name;
  final int score;
  final int masjidCount;
  final String dateLabel;

  static const _teal = Color(0xFF0F7C68);
  static const _darkTeal = Color(0xFF0A5244);
  static const _lightBg = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _lightBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _teal, width: 2),
      ),
      child: Stack(
        children: [
          // Inner thin border
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _teal.withValues(alpha: 0.25),
                    width: 0.8,
                  ),
                ),
              ),
            ),
          ),
          // Islamic geometric corner ornaments
          Positioned(
            top: 0,
            left: 0,
            child: CustomPaint(
              size: const Size(64, 64),
              painter: _IslamicCornerPainter(flip: false, flipV: false),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: CustomPaint(
              size: const Size(64, 64),
              painter: _IslamicCornerPainter(flip: true, flipV: false),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: CustomPaint(
              size: const Size(64, 64),
              painter: _IslamicCornerPainter(flip: false, flipV: true),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: CustomPaint(
              size: const Size(64, 64),
              painter: _IslamicCornerPainter(flip: true, flipV: true),
            ),
          ),
          // Main content
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 16, 40, 14),
            child: Column(
              children: [
                // Logo + App name
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/namaz-near-me-icon.png',
                    width: 48,
                    height: 48,
                    errorBuilder: (_, __, ___) => Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _teal,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.mosque,
                          color: Colors.white, size: 28),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'NAMAZ NEAR ME',
                  style: const TextStyle(
                    fontFamily: 'Cinzel',
                    color: _darkTeal,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  'Nearby Masjids & Jamaat Timings',
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    color: _teal,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                // Title
                Text(
                  'CERTIFICATE OF APPRECIATION',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Cinzel',
                    color: _teal,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                // Recipient name — centered
                Column(
                  children: [
                    Text(
                      'To',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Lato',
                        color: Color(0xFF555555),
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name.isNotEmpty ? name : 'Volunteer',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'GreatVibes',
                        color: _darkTeal,
                        fontSize: 36,
                        height: 1.1,
                      ),
                    ),
                    Container(
                      width: 200,
                      height: 1,
                      color: _teal.withValues(alpha: 0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Body text
                Text(
                  'In appreciation of your participation and contribution\nto the Namaz Near Me app.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    color: Color(0xFF444444),
                    fontSize: 11,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'May Allah accept this as sadqa-e-jariya.  Ameen.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    color: _darkTeal,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                // Hadith line
                Row(
                  children: [
                    Expanded(
                      child: Container(
                          height: 0.8, color: _teal.withValues(alpha: 0.3)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'مَنْ دَلَّ عَلَى خَيْرٍ فَلَهُ مِثْلُ أَجْرِ فَاعِلِهِ',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: _teal,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                          height: 0.8, color: _teal.withValues(alpha: 0.3)),
                    ),
                  ],
                ),
                Text(
                  '"One who guides others to good has a reward equal to its doer."  — Sahih Muslim',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    color: Color(0xFF777777),
                    fontSize: 9,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
                const Spacer(),
                // Footer
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _CertificateFooterBlock(title: 'DATE', value: dateLabel),
                    const Spacer(),
                    _CertificateSeal(score: score, masjidCount: masjidCount),
                    const Spacer(),
                    _CertificateAppLinks(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CertificateAppLinks extends StatelessWidget {
  const _CertificateAppLinks();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'DOWNLOAD APP',
          style: TextStyle(
            fontSize: 7,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0F7C68).withValues(alpha: 0.7),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Android
            Column(
              children: [
                QrImageView(
                  data: _namazAndroidAppUrl,
                  version: QrVersions.auto,
                  size: 44,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF0F7C68),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.android,
                        size: 8, color: Color(0xFF3DDC84)),
                    const SizedBox(width: 2),
                    Text('Android',
                        style: TextStyle(
                            fontSize: 7,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 8),
            // iOS
            Column(
              children: [
                QrImageView(
                  data: _namazIosAppUrl,
                  version: QrVersions.auto,
                  size: 44,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF0F7C68),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.apple, size: 8, color: Colors.black54),
                    const SizedBox(width: 2),
                    Text('iPhone',
                        style: TextStyle(
                            fontSize: 7,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _IslamicCornerPainter extends CustomPainter {
  const _IslamicCornerPainter({required this.flip, required this.flipV});
  final bool flip;
  final bool flipV;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (flip) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    if (flipV) {
      canvas.translate(0, size.height);
      canvas.scale(1, -1);
    }

    const c1 = Color(0xFF0F7C68);
    const c2 = Color(0xFF2AB5A0);
    const c3 = Color(0xFF84D4C8);

    final p1 = Paint()..color = c1;
    final p2 = Paint()..color = c2;
    final p3 = Paint()..color = c3;

    // Large triangle
    final t1 = Path()
      ..moveTo(0, 0)
      ..lineTo(40, 0)
      ..lineTo(0, 40)
      ..close();
    canvas.drawPath(t1, p1);

    // Medium triangle
    final t2 = Path()
      ..moveTo(0, 28)
      ..lineTo(28, 0)
      ..lineTo(52, 0)
      ..lineTo(0, 52)
      ..close();
    canvas.drawPath(t2, p2);

    // Small triangle
    final t3 = Path()
      ..moveTo(0, 44)
      ..lineTo(20, 44)
      ..lineTo(0, 64)
      ..close();
    canvas.drawPath(t3, p3);

    final t4 = Path()
      ..moveTo(44, 0)
      ..lineTo(64, 0)
      ..lineTo(44, 20)
      ..close();
    canvas.drawPath(t4, p3);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CertificateFooterBlock extends StatelessWidget {
  const _CertificateFooterBlock({
    required this.title,
    required this.value,
    this.alignRight = false,
  });

  final String title;
  final String value;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 98,
      child: Column(
        crossAxisAlignment:
            alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(height: 1.2, color: const Color(0xFFB9CDD0)),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: alignRight ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              color: Color(0xFF8B949C),
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            textAlign: alignRight ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              color: Color(0xFF343A40),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              height: 1.12,
            ),
          ),
        ],
      ),
    );
  }
}

class _CertificateSeal extends StatelessWidget {
  const _CertificateSeal({required this.score, required this.masjidCount});

  final int score;
  final int masjidCount;

  @override
  Widget build(BuildContext context) {
    final badgeLabel = score >= 1000
        ? 'AMBASSADOR'
        : score >= 100
            ? 'DIAMOND'
            : score >= 10 || masjidCount > 0
                ? 'GOLD'
                : score >= 5
                    ? 'SILVER'
                    : 'BRONZE';
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF9F7),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF2AB5A8), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F7C68).withValues(alpha: .14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipOval(
            child: Image.asset(
              'assets/images/namaz-near-me-icon.png',
              width: 34,
              height: 34,
            ),
          ),
          Positioned(
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE9A8),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeLabel,
                style: const TextStyle(
                  color: Color(0xFF80620A),
                  fontSize: 5.6,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
