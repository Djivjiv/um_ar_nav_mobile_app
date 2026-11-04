import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth/auth_cubit.dart';

/// Checks the account again each time the app returns to the foreground, so
/// an account deactivated or approved while the app is open takes effect.
class AccountAccessWatcher extends StatefulWidget {
  final Widget child;

  const AccountAccessWatcher({super.key, required this.child});

  @override
  State<AccountAccessWatcher> createState() => _AccountAccessWatcherState();
}

class _AccountAccessWatcherState extends State<AccountAccessWatcher>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AuthCubit>().recheckAccess();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
