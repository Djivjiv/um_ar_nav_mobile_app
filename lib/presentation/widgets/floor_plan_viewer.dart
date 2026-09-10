import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/indoor_node_model.dart';
import 'indoor_path_painter.dart';

/// Pan/zoom viewer for a floor-plan image with node overlays and tap-to-select.
class FloorPlanViewer extends StatefulWidget {
  final String? imageUrl;
  final List<IndoorNodeModel> nodes;
  final List<Offset> pathPixels;
  final String? selectedNodeId;
  final ValueChanged<IndoorNodeModel> onNodeTap;

  const FloorPlanViewer({
    super.key,
    required this.imageUrl,
    required this.nodes,
    required this.onNodeTap,
    this.pathPixels = const [],
    this.selectedNodeId,
  });

  @override
  State<FloorPlanViewer> createState() => _FloorPlanViewerState();
}

class _FloorPlanViewerState extends State<FloorPlanViewer> {
  final TransformationController _controller = TransformationController();
  Size? _imageSize;
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final s = _controller.value.getMaxScaleOnAxis();
      if ((s - _scale).abs() > 0.05) setState(() => _scale = s);
    });
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant FloorPlanViewer old) {
    super.didUpdateWidget(old);
    if (old.imageUrl != widget.imageUrl) {
      _imageSize = null;
      _resolveImage();
    }
  }

  void _resolveImage() {
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) return;
    final provider = CachedNetworkImageProvider(widget.imageUrl!);
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _imageSize = Size(
              info.image.width.toDouble(),
              info.image.height.toDouble(),
            ));
      }
      stream.removeListener(listener);
    }, onError: (_, _) => stream.removeListener(listener));
    stream.addListener(listener);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) {
      return const _NoPlan();
    }
    final imgSize = _imageSize;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Fit the image within the viewport preserving aspect ratio.
        Size renderSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (imgSize != null) {
          final ar = imgSize.width / imgSize.height;
          final boxAr = constraints.maxWidth / constraints.maxHeight;
          if (ar > boxAr) {
            renderSize = Size(constraints.maxWidth, constraints.maxWidth / ar);
          } else {
            renderSize =
                Size(constraints.maxHeight * ar, constraints.maxHeight);
          }
        }

        return InteractiveViewer(
          transformationController: _controller,
          minScale: 0.3,
          maxScale: 5.0,
          boundaryMargin: const EdgeInsets.all(200),
          child: Center(
            child: SizedBox(
              width: renderSize.width,
              height: renderSize.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _handleTap(d.localPosition, renderSize),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: widget.imageUrl!,
                      fit: BoxFit.fill,
                      placeholder: (_, _) => const ColoredBox(
                        color: AppColors.backgroundGray,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (_, _, _) => const _NoPlan(),
                    ),
                    if (imgSize != null)
                      CustomPaint(
                        painter: IndoorPathPainter(
                          imageSize: imgSize,
                          nodes: widget.nodes,
                          pathPoints: widget.pathPixels,
                          selectedNodeId: widget.selectedNodeId,
                          zoomScale: _scale,
                        ),
                      ),
                    if (imgSize != null)
                      ..._infoLabels(imgSize, renderSize),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _infoLabels(Size imgSize, Size renderSize) {
    final sx = renderSize.width / imgSize.width;
    final sy = renderSize.height / imgSize.height;
    final fontSize = (10 * _scale).clamp(7.0, 14.0);

    return widget.nodes.where((n) => !n.isNavigable).map((n) {
      final left = n.x * sx;
      final top = n.y * sy;
      return Positioned(
        left: left - 40,
        top: top - 9,
        width: 80,
        child: GestureDetector(
          onTap: () => widget.onNodeTap(n),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              n.displayLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize.toDouble(),
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  void _handleTap(Offset local, Size renderSize) {
    final imgSize = _imageSize;
    if (imgSize == null) return;
    final px = local.dx / renderSize.width * imgSize.width;
    final py = local.dy / renderSize.height * imgSize.height;

    IndoorNodeModel? nearest;
    double best = 28; // px in image space
    for (final n in widget.nodes) {
      if (!n.isNavigable) continue;
      final d = (Offset(n.x, n.y) - Offset(px, py)).distance;
      if (d < best) {
        best = d;
        nearest = n;
      }
    }
    if (nearest != null) widget.onNodeTap(nearest);
  }
}

class _NoPlan extends StatelessWidget {
  const _NoPlan();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.backgroundGray,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 48, color: AppColors.textSecondary),
            SizedBox(height: 8),
            Text('Floor plan image not available',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
