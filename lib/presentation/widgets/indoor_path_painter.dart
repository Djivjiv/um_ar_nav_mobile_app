import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/indoor_node_model.dart';

/// Paints indoor navigation nodes and the computed path over a floor-plan
/// image. All coordinates are in the floor plan's native pixel space; the
/// painter scales them to [imageSize] rendered at the current widget size.
class IndoorPathPainter extends CustomPainter {
  final Size imageSize;
  final List<IndoorNodeModel> nodes;

  /// Path points packed as Offset(x, y) in image pixel space.
  final List<Offset> pathPoints;
  final String? selectedNodeId;
  final double zoomScale;

  IndoorPathPainter({
    required this.imageSize,
    required this.nodes,
    this.pathPoints = const [],
    this.selectedNodeId,
    this.zoomScale = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;
    final sx = size.width / imageSize.width;
    final sy = size.height / imageSize.height;
    Offset map(Offset p) => Offset(p.dx * sx, p.dy * sy);

    // ── Path ──
    if (pathPoints.length >= 2) {
      final path = Path()..moveTo(map(pathPoints.first).dx, map(pathPoints.first).dy);
      for (final p in pathPoints.skip(1)) {
        final m = map(p);
        path.lineTo(m.dx, m.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.googleMapsBlue.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.googleMapsBlue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // ── Navigable nodes as coloured dots ──
    for (final n in nodes) {
      if (!n.isNavigable) continue;
      final c = map(Offset(n.x, n.y));
      final color = _dotColor(n.label ?? n.name);
      canvas.drawCircle(c, 6, Paint()..color = Colors.white);
      canvas.drawCircle(c, 5, Paint()..color = color);
      if (n.id == selectedNodeId) {
        canvas.drawCircle(
          c,
          10,
          Paint()
            ..color = AppColors.accentGold
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }
  }

  Color _dotColor(String? label) {
    switch ((label ?? '').toLowerCase()) {
      case 'entrance':
        return AppColors.successGreen;
      case 'pathway':
        return AppColors.accentGold;
      case 'stairs':
        return AppColors.primaryMaroon;
      case 'elevator':
        return AppColors.infoBlue;
      case 'girlsrestroom':
        return const Color(0xFFE91E8C);
      case 'boyrestroom':
        return AppColors.infoBlue;
      default:
        return AppColors.accentGold;
    }
  }

  @override
  bool shouldRepaint(covariant IndoorPathPainter old) {
    return old.pathPoints != pathPoints ||
        old.selectedNodeId != selectedNodeId ||
        old.nodes != nodes ||
        old.imageSize != imageSize;
  }
}
