import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// Message payloads exchanged with the (not-yet-wired) Unity AR player.
///
/// These are plain Dart data classes with no dependency on
/// `flutter_unity_widget` or any other AR package — they only describe the
/// JSON shape both sides agree on, so they're safe to use regardless of
/// which native AR bridge ends up rendering the scene. See
/// `unity_ar_screen.dart` for why the Unity bridge itself isn't wired up
/// yet.

/// Contract for every message sent Flutter → Unity.
abstract class AROutgoingMessage {
  String get type;
  Map<String, dynamic> toJson();
  String toJsonString() => jsonEncode(toJson());
}

/// Tells Unity to start outdoor GPS-arrow guidance toward a building.
class ARStartMessage implements AROutgoingMessage {
  @override
  String get type => 'start_outdoor';

  final String buildingId;
  final String destinationName;
  final List<LatLng> outdoorWaypoints;

  const ARStartMessage({
    required this.buildingId,
    required this.destinationName,
    required this.outdoorWaypoints,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'buildingId': buildingId,
        'destinationName': destinationName,
        'outdoorWaypoints': outdoorWaypoints
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
      };

  @override
  String toJsonString() => jsonEncode(toJson());
}

/// One node along an indoor path, in the Unity scene's local coordinates.
class ARIndoorNode {
  final String id;
  final double unityX;
  final double unityY;
  final double unityZ;
  final String? label;

  const ARIndoorNode({
    required this.id,
    required this.unityX,
    required this.unityY,
    required this.unityZ,
    this.label,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'unity_x': unityX,
        'unity_y': unityY,
        'unity_z': unityZ,
        if (label != null) 'label': label,
      };
}

/// Tells Unity to start node-based indoor AR arrows through a building.
class ARIndoorMessage implements AROutgoingMessage {
  @override
  String get type => 'start_indoor';

  final String buildingId;
  final int floorNumber;
  final String destinationName;
  final List<ARIndoorNode> indoorPath;

  const ARIndoorMessage({
    required this.buildingId,
    required this.floorNumber,
    required this.destinationName,
    required this.indoorPath,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'buildingId': buildingId,
        'floorNumber': floorNumber,
        'destinationName': destinationName,
        'indoorPath': indoorPath.map((n) => n.toJson()).toList(),
      };

  @override
  String toJsonString() => jsonEncode(toJson());
}

/// Contract for every message received Unity → Flutter.
abstract class ARIncomingMessage {
  final String type;
  const ARIncomingMessage(this.type);
}

/// Unity reports the user reached their destination.
class ARArrivedMessage extends ARIncomingMessage {
  final String destination;

  const ARArrivedMessage({required this.destination}) : super('arrived');

  factory ARArrivedMessage.fromJson(Map<String, dynamic> json) =>
      ARArrivedMessage(destination: json['destination'] as String? ?? '');
}

/// Unity reports a QR code was scanned (e.g. an indoor entry marker).
class ARQRScannedMessage extends ARIncomingMessage {
  final String buildingId;
  final int floor;
  final String nodeId;

  const ARQRScannedMessage({
    required this.buildingId,
    required this.floor,
    required this.nodeId,
  }) : super('qr_scanned');

  factory ARQRScannedMessage.fromJson(Map<String, dynamic> json) =>
      ARQRScannedMessage(
        buildingId: json['buildingId']?.toString() ?? '',
        floor: (json['floor'] as num?)?.toInt() ?? 1,
        nodeId: json['nodeId']?.toString() ?? '',
      );
}

/// Unity reports an internal error.
class ARErrorMessage extends ARIncomingMessage {
  final String message;

  const ARErrorMessage({required this.message}) : super('error');

  factory ARErrorMessage.fromJson(Map<String, dynamic> json) =>
      ARErrorMessage(message: json['message'] as String? ?? 'Unknown error');
}

/// Parses a raw JSON string received from Unity into the matching typed
/// message, or `null` if the type is unrecognized or the JSON is malformed.
ARIncomingMessage? parseARIncomingMessage(String raw) {
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    switch (json['type']) {
      case 'arrived':
        return ARArrivedMessage.fromJson(json);
      case 'qr_scanned':
        return ARQRScannedMessage.fromJson(json);
      case 'error':
        return ARErrorMessage.fromJson(json);
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}
