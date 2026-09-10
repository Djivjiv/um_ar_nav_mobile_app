import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/about_um_model.dart';
import '../../../data/repositories/about_repository.dart';
import '../../widgets/loading_skeleton.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late Future<AboutUmModel> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AboutRepository>().getAbout();
  }

  /// Contact values arrive raw (a phone number, an email, a bare domain) —
  /// pick the right scheme, then launch.
  Future<void> _launchContactUrl(String url) async {
    try {
      final raw = url.trim();
      String target;
      if (raw.startsWith('+') || raw.startsWith('0')) {
        target = 'tel:$raw';
      } else if (raw.contains('@') && !raw.startsWith('http')) {
        target = 'mailto:$raw';
      } else if (!raw.startsWith('http')) {
        target = 'https://$raw';
      } else {
        target = raw;
      }
      final uri = Uri.parse(target);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Contact launch error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: FutureBuilder<AboutUmModel>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _AboutLoading();
          }
          final a = snap.data ?? AboutUmModel.fallback;
          return ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              // ── Header ──
              Container(
                width: double.infinity,
                color: AppColors.primaryMaroon,
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 8),
                        ],
                      ),
                      child: ClipOval(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Image.asset('assets/images/umlogo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Icon(
                                  Icons.school,
                                  color: AppColors.primaryMaroon,
                                  size: 44)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('University of Mindanao',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(a.location ?? 'Matina Campus',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.accentGold,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ── Mission / Vision ──
              if (a.mission != null)
                _borderedCard('MISSION', a.mission!),
              if (a.vision != null) _borderedCard('VISION', a.vision!),

              // ── Core Values ──
              if (a.coreValues.isNotEmpty) ...[
                _sectionHeader('Core Values'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: a.coreValues
                        .map((v) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.primaryMaroon,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.1),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2)),
                                ],
                              ),
                              child: Text(v,
                                  style: const TextStyle(
                                      color: AppColors.accentGold,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ))
                        .toList(),
                  ),
                ),
              ],

              // ── Key facts ──
              _sectionHeader('Key Facts'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 2.2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    _fact('Founded', a.founded ?? ''),
                    _fact('Campus', a.campusSize ?? ''),
                    _fact('Location', a.location ?? ''),
                    _fact('Ranking', a.ranking ?? ''),
                  ],
                ),
              ),

              // ── Contact ──
              if (a.phone != null || a.email != null || a.website != null)
                _sectionHeader('Contact'),
              if (a.phone != null)
                _contactRow(Icons.phone, a.phone!),
              if (a.email != null)
                _contactRow(Icons.email, a.email!),
              if (a.website != null)
                _contactRow(Icons.language, a.website!),

              // ── Social ──
              if (a.facebook != null ||
                  a.instagram != null ||
                  a.twitter != null) ...[
                _sectionHeader('Connect'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _socialButton(Icons.facebook, const Color(0xFF1877F2),
                          a.facebook, 'Facebook'),
                      const SizedBox(width: 16),
                      _socialButton(Icons.camera_alt, const Color(0xFFE1306C),
                          a.instagram, 'Instagram'),
                      const SizedBox(width: 16),
                      _socialButton(Icons.alternate_email,
                          const Color(0xFF1DA1F2), a.twitter, 'Twitter/X'),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(title,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryMaroon,
              letterSpacing: 0.3)),
    );
  }

  Widget _borderedCard(String title, String body) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: AppColors.accentGold, width: 4),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.primaryMaroon,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Text(body,
              style: const TextStyle(
                  fontSize: 14, color: Color(0xFF3D3D3D), height: 1.5)),
        ],
      ),
    );
  }

  Widget _fact(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8D5B0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B6B6B),
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Flexible(
            child: Text(value.isEmpty ? 'N/A' : value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _contactRow(IconData icon, String value) {
    return InkWell(
      onTap: () => _launchContactUrl(value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primaryMaroon.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.primaryMaroon, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF1A1A1A))),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 14, color: Color(0xFF6B6B6B)),
          ],
        ),
      ),
    );
  }

  Widget _socialButton(
      IconData icon, Color color, String? url, String platformName) {
    final enabled = url != null && url.isNotEmpty;
    return GestureDetector(
      onTap: () async {
        if (!enabled) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$platformName link not available'),
            backgroundColor: AppColors.primaryMaroon,
          ));
          return;
        }
        var cleanUrl = url.trim();
        if (!cleanUrl.startsWith('http://') &&
            !cleanUrl.startsWith('https://')) {
          cleanUrl = 'https://$cleanUrl';
        }
        try {
          final uri = Uri.parse(cleanUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Cannot open $platformName'),
              backgroundColor: AppColors.primaryMaroon,
            ));
          }
        } catch (e) {
          debugPrint('Launch URL error: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Cannot open $platformName'),
              backgroundColor: AppColors.primaryMaroon,
            ));
          }
        }
      },
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: enabled ? color : Colors.grey[300],
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

class _AboutLoading extends StatelessWidget {
  const _AboutLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        LoadingSkeleton(height: 160),
        SizedBox(height: 16),
        LoadingSkeleton(height: 90),
        SizedBox(height: 12),
        LoadingSkeleton(height: 90),
      ],
    );
  }
}
