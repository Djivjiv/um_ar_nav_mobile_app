import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/floor_plan_model.dart';
import '../../data/repositories/floor_plan_repository.dart';
import '../bloc/auth/auth_cubit.dart';

/// Opens the floor plan viewer for a building, after a short chooser when it
/// has several plans. Takes no space for those [canSeeIndoorMap] says no to,
/// who never load the plans, or when the building has no plan to show.
class FloorPlansButton extends StatelessWidget {
  final int buildingId;

  const FloorPlansButton({super.key, required this.buildingId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      buildWhen: (a, b) => canSeeIndoorMap(a) != canSeeIndoorMap(b),
      builder: (context, auth) => canSeeIndoorMap(auth)
          ? _PlansButton(key: ValueKey(buildingId), buildingId: buildingId)
          : const SizedBox.shrink(),
    );
  }
}

class _PlansButton extends StatefulWidget {
  final int buildingId;

  const _PlansButton({super.key, required this.buildingId});

  @override
  State<_PlansButton> createState() => _PlansButtonState();
}

class _PlansButtonState extends State<_PlansButton> {
  List<FloorPlanModel> _plans = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // The repository falls back to the saved offline copy.
      final floors = await context
          .read<FloorPlanRepository>()
          .getFloorsForBuilding(widget.buildingId);
      if (!mounted) return;
      // A floor without an image has nothing to show in the viewer.
      setState(() => _plans = floors
          .where((f) => f.imageUrl?.trim().isNotEmpty == true)
          .toList());
    } catch (e) {
      debugPrint('Floor plans button: $e');
    }
  }

  Future<void> _open() async {
    final router = GoRouter.of(context);
    final plan = _plans.length == 1
        ? _plans.single
        : await showModalBottomSheet<FloorPlanModel>(
            context: context,
            useRootNavigator: true,
            builder: (_) => _FloorChooser(plans: _plans),
          );
    if (plan == null) return;
    router.push('/floor-plan/${plan.id}?buildingId=${widget.buildingId}');
  }

  @override
  Widget build(BuildContext context) {
    if (_plans.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        onPressed: _open,
        icon: const Icon(Icons.layers_outlined),
        label: const Text('Floor plans'),
      ),
    );
  }
}

class _FloorChooser extends StatelessWidget {
  final List<FloorPlanModel> plans;

  const _FloorChooser({required this.plans});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const ListTile(
            title: Text('Choose a floor',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          for (final plan in plans)
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: Text(plan.tabLabel),
              onTap: () => Navigator.of(context).pop(plan),
            ),
        ],
      ),
    );
  }
}
