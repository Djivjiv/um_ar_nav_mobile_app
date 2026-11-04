import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth/auth_cubit.dart';

/// Checks a visitor's session every few seconds and on each return to the
/// app, whichever screen is open, so it ends as soon as its time is up.
class VisitorExpiryWatcher extends StatefulWidget {
  final Widget child;

  const VisitorExpiryWatcher({super.key, required this.child});

  static const Duration checkEvery = Duration(seconds: 5);

  @override
  State<VisitorExpiryWatcher> createState() => _VisitorExpiryWatcherState();
}

class _VisitorExpiryWatcherState extends State<VisitorExpiryWatcher>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(VisitorExpiryWatcher.checkEvery, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  void _check() => context.read<AuthCubit>().checkVisitorSession();

  @override
  Widget build(BuildContext context) => widget.child;
}
