import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/services/instruction_service.dart';
import '../../bloc/navigation/outdoor_nav_cubit.dart';

class ArScreen extends StatefulWidget {
  const ArScreen({super.key});

  @override
  State<ArScreen> createState() => _ArScreenState();
}

class _ArScreenState extends State<ArScreen> {
  double _heading = 0;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OutdoorNavCubit, OutdoorNavState>(
      builder: (context, nav) {
        final hasRoute = nav.hasRoute && nav.instructions.isNotEmpty;
        final step = hasRoute
            ? nav.currentStep.clamp(0, nav.instructions.length - 1)
            : 0;
        final current = hasRoute ? nav.instructions[step] : null;
        final next = hasRoute && step < nav.instructions.length - 1
            ? nav.instructions[step + 1]
            : null;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Camera placeholder.
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Icon(Icons.videocam_off_outlined,
                        color: Colors.white24, size: 64),
                  ),
                ),
              ),

              // Directional arrow.
              Center(
                child: StreamBuilder<CompassEvent>(
                  stream: FlutterCompass.events,
                  builder: (context, snap) {
                    _heading = snap.data?.heading ?? _heading;
                    final target = current?.bearing ?? 0;
                    final relative =
                        ((target - _heading) * math.pi / 180);
                    return Transform.rotate(
                      angle: relative,
                      child: Icon(
                        current?.direction == 'arrive'
                            ? Icons.location_on
                            : Icons.navigation,
                        size: 130,
                        color: AppColors.accentGold,
                      ),
                    );
                  },
                ),
              ),

              // Top bar.
              SafeArea(
                child: Container(
                  color: AppColors.primaryMaroon,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.white),
                        onPressed: () => context.go('/map'),
                      ),
                      const Text('AR Navigation',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accentGold,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('BETA',
                            style: TextStyle(
                                color: AppColors.primaryMaroon,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),

              // Bottom panel.
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  color: AppColors.primaryMaroon.withValues(alpha: 0.92),
                  padding: EdgeInsets.fromLTRB(
                      20, 16, 20, MediaQuery.of(context).padding.bottom + 90),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        current?.instructionText ??
                            'Set a destination on the map to start AR guidance.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                      if (next != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Next: ${InstructionService.label(next.direction)}',
                          style:
                              const TextStyle(color: AppColors.accentGold),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (hasRoute)
                        Text('Step ${step + 1} of ${nav.instructions.length}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => context.go('/map'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                        child: const Text('Switch to 2D Map'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
