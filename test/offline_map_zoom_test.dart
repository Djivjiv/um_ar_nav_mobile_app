import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/core/config/maptiler_config.dart';
import 'package:um_ar_mobile_app/core/network/connectivity_service.dart';
import 'package:um_ar_mobile_app/data/local/campus_tile_cache.dart';
import 'package:um_ar_mobile_app/presentation/widgets/um_map_widget.dart';

void main() {
  late ConnectivityService connectivity;
  late MapController map;

  setUp(() {
    connectivity = ConnectivityService(probe: () async => true);
    map = MapController();
  });

  Future<void> pumpMap(WidgetTester tester, {double zoom = 15}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UmMapWidget(
          controller: map,
          initialZoom: zoom,
          connectivity: connectivity,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  Future<void> tearDownMap(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  test('the limit is the lowest zoom saved on the phone', () {
    expect(MapTilerConfig.offlineMinZoom, CampusTileCache().minZoom);
    expect(MapTilerConfig.minZoomFor(online: true), MapTilerConfig.minZoom);
    expect(MapTilerConfig.minZoomFor(online: false), 16);
  });

  testWidgets('online, the map zooms out as before', (tester) async {
    await pumpMap(tester, zoom: 15);

    map.move(map.camera.center, MapTilerConfig.minZoom);
    await tester.pump();

    expect(map.camera.zoom, MapTilerConfig.minZoom);

    await tearDownMap(tester);
  });

  testWidgets('losing the connection below 16 moves the map in',
      (tester) async {
    await pumpMap(tester, zoom: 15);
    expect(map.camera.zoom, 15);

    connectivity.reportOffline();
    await tester.pump();
    await tester.pump();

    expect(map.camera.zoom, 16);

    await tearDownMap(tester);
  });

  testWidgets('offline, it can not be zoomed out below 16', (tester) async {
    await pumpMap(tester, zoom: 17.5);

    connectivity.reportOffline();
    await tester.pump();
    await tester.pump();
    expect(map.camera.zoom, 17.5);

    map.move(map.camera.center, 15);
    await tester.pump();

    expect(map.camera.zoom, 16);

    await tearDownMap(tester);
  });

  testWidgets('a map opened offline starts at 16 or above', (tester) async {
    connectivity.reportOffline();

    await pumpMap(tester, zoom: 15);

    expect(map.camera.zoom, 16);

    await tearDownMap(tester);
  });

  testWidgets('back online, the full range returns', (tester) async {
    await pumpMap(tester, zoom: 17);
    connectivity.reportOffline();
    await tester.pump();
    await tester.pump();

    connectivity.reportOnline();
    await tester.pump();
    await tester.pump();
    map.move(map.camera.center, 15);
    await tester.pump();

    expect(map.camera.zoom, 15);

    await tearDownMap(tester);
  });
}
