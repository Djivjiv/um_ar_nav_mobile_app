import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../core/constants/app_colors.dart';

class _Page {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Page(this.icon, this.title, this.subtitle);
}

const _pages = [
  _Page(Icons.map_rounded, 'Navigate UM Campus',
      'Find your way around University of Mindanao Matina Campus with ease'),
  _Page(Icons.view_in_ar_rounded, 'AR Directions',
      'Point your camera and follow the arrows to your destination'),
  _Page(Icons.meeting_room_rounded, 'Indoor Floor Plans',
      'Explore building interiors with detailed floor plans and room information'),
  _Page(Icons.rocket_launch_rounded, 'Ready to Explore?',
      'Login with your school email or continue as visitor'),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  Future<void> _finish(String route) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    if (mounted) context.go(route);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _finish('/login'),
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            color: AppColors.primaryMaroon
                                .withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(p.icon,
                              size: 76, color: AppColors.primaryMaroon),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          p.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          p.subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.textSecondary, height: 1.5),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            SmoothPageIndicator(
              controller: _controller,
              count: _pages.length,
              effect: const ExpandingDotsEffect(
                activeDotColor: AppColors.primaryMaroon,
                dotColor: Color(0xFFD9CDBF),
                dotHeight: 8,
                dotWidth: 8,
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: last
                  ? Column(
                      children: [
                        ElevatedButton(
                          onPressed: () => _finish('/login'),
                          child: const Text('Login with School Email'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: () => _finish('/visitor'),
                          child: const Text('Continue as Visitor'),
                        ),
                      ],
                    )
                  : ElevatedButton(
                      onPressed: () => _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      ),
                      child: const Text('Next'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
