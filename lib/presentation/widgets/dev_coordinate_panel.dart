import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

/// Development only ([kDevCoordinateTools]): where the phone thinks it is, to
/// correct AR nodes in the admin app. Nothing here leaves the phone.
class DevCoordinatePanel extends StatelessWidget {
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final double? heading;

  const DevCoordinatePanel({
    super.key,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.heading,
  });

  static const int maxMarks = 6;

  /// Marked points, newest first. Shared by every panel, so they are still
  /// there after moving between the map and AR, until the app closes.
  static final ValueNotifier<List<String>> marks = ValueNotifier(const []);

  static String format(double latitude, double longitude) =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

  static const _text = TextStyle(
    color: Colors.greenAccent,
    fontFamily: 'monospace',
    fontSize: 10.5,
    height: 1.35,
  );

  String? get _coordinates {
    final lat = latitude;
    final lng = longitude;
    return lat == null || lng == null ? null : format(lat, lng);
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Copied $text'),
        duration: const Duration(seconds: 1),
      ));
  }

  void _mark(BuildContext context, String text) {
    marks.value = [text, ...marks.value].take(maxMarks).toList();
    _copy(context, text);
  }

  Widget _button(String label, VoidCallback? onPressed) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 11),
        ),
        child: Text(label),
      );

  @override
  Widget build(BuildContext context) {
    final coordinates = _coordinates;
    final acc = accuracy;
    final deg = heading;
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 190,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'lat  ${latitude?.toStringAsFixed(6) ?? '—'}\n'
              'lng  ${longitude?.toStringAsFixed(6) ?? '—'}\n'
              'acc  ${acc == null ? '—' : '±${acc.toStringAsFixed(1)} m'}\n'
              'hdg  ${deg == null ? '—' : '${deg.toStringAsFixed(0)}°'}',
              style: _text,
            ),
            Wrap(
              children: [
                _button(
                  'Copy',
                  coordinates == null
                      ? null
                      : () => _copy(context, coordinates),
                ),
                _button(
                  'Mark point',
                  coordinates == null
                      ? null
                      : () => _mark(context, coordinates),
                ),
              ],
            ),
            ValueListenableBuilder<List<String>>(
              valueListenable: marks,
              builder: (context, points, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final point in points)
                    InkWell(
                      onTap: () => _copy(context, point),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(point, style: _text),
                      ),
                    ),
                  if (points.isNotEmpty)
                    _button('Clear', () => marks.value = const []),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [DevCoordinatePanel] for a screen with no GPS or compass of its own.
///
/// The position is read on a timer, not from `getPositionStream`: on Android
/// that stream is shared, and the first listener's settings apply to all of
/// them, which would change the GPS settings of a trip started over the map.
/// Both stop while another screen covers this one.
class DevLiveCoordinatePanel extends StatefulWidget {
  final Future<Position> Function()? readPosition;
  final Stream<double?>? headings;

  const DevLiveCoordinatePanel({super.key, this.readPosition, this.headings});

  static const Duration interval = Duration(seconds: 2);

  @override
  State<DevLiveCoordinatePanel> createState() => _DevLiveCoordinatePanelState();
}

class _DevLiveCoordinatePanelState extends State<DevLiveCoordinatePanel> {
  Timer? _timer;
  StreamSubscription<double?>? _headingSub;
  bool _reading = false;
  Position? _position;
  double? _heading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TickerMode.valuesOf(context).enabled) {
      _start();
    } else {
      _stop();
    }
  }

  void _start() {
    if (_timer != null) return;
    _timer = Timer.periodic(DevLiveCoordinatePanel.interval, (_) => _read());
    _headingSub = (widget.headings ?? _compass()).listen(
      (h) {
        if (mounted) setState(() => _heading = h);
      },
      onError: (Object e) => debugPrint('Coordinates panel compass: $e'),
    );
    _read();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _headingSub?.cancel();
    _headingSub = null;
  }

  Stream<double?> _compass() =>
      FlutterCompass.events?.map((e) => e.heading) ?? const Stream.empty();

  Future<Position> _gps() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
  }

  Future<void> _read() async {
    if (_reading) return;
    _reading = true;
    try {
      final position = await (widget.readPosition ?? _gps)();
      if (mounted && _timer != null) setState(() => _position = position);
    } catch (e) {
      debugPrint('Coordinates panel GPS: $e');
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _position;
    return DevCoordinatePanel(
      latitude: p?.latitude,
      longitude: p?.longitude,
      accuracy: p?.accuracy,
      heading: _heading,
    );
  }
}
