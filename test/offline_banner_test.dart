import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:um_ar_mobile_app/core/network/connectivity_service.dart';
import 'package:um_ar_mobile_app/presentation/widgets/offline_banner.dart';

void main() {
  group('offlineMessage', () {
    final now = DateTime(2026, 10, 28, 16, 30);

    test('same day shows only the time', () {
      expect(
        OfflineBanner.offlineMessage(DateTime(2026, 10, 28, 9, 5), now: now),
        'Offline: showing saved data, last updated 09:05',
      );
    });

    test('an earlier day shows the date too', () {
      expect(
        OfflineBanner.offlineMessage(DateTime(2026, 10, 27, 14, 0), now: now),
        'Offline: showing saved data, last updated Oct 27, 14:00',
      );
    });

    test('unknown time', () {
      expect(OfflineBanner.offlineMessage(null),
          'Offline: showing saved data');
    });
  });

  testWidgets('banner appears offline and hides when back online',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final connectivity = ConnectivityService(probe: () async => true);
    await tester.pumpWidget(MaterialApp(
      home: OfflineBanner(
        connectivity: connectivity,
        child: const Scaffold(body: Text('Map')),
      ),
    ));
    expect(find.textContaining('Offline'), findsNothing);
    expect(find.text('Map'), findsOneWidget);

    connectivity.reportOffline();
    connectivity.reportServedFromCache(DateTime.now());
    await tester.pump();
    expect(find.textContaining('Offline: showing saved data'), findsOneWidget);
    // Non-blocking: the page is still there underneath.
    expect(find.text('Map'), findsOneWidget);

    connectivity.reportOnline();
    await tester.pump();
    expect(find.textContaining('Offline'), findsNothing);
  });
}
