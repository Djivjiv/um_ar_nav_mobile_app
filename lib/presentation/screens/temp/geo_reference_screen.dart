// ⚠️ TEMPORARY floor-plan georeferencing tool — remove after data collection.
//
// Step 2 + upload: building + floor selector + floor-plan image upload.
// Requires in Supabase:
//   alter table building_floors
//     add column if not exists reference_points jsonb default '[]'::jsonb;
//   + a PUBLIC Storage bucket named `floor-plans`.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GeoReferenceScreen extends StatefulWidget {
  const GeoReferenceScreen({super.key});

  @override
  State<GeoReferenceScreen> createState() => _GeoReferenceScreenState();
}

class _GeoReferenceScreenState extends State<GeoReferenceScreen> {
  List<dynamic> _buildings = [];
  dynamic _selectedBuilding;
  dynamic _selectedFloor;
  final _floorNumberController = TextEditingController();
  int? _floorNumber;
  bool _isLoading = false;
  bool _isUploading = false;
  File? _selectedImageFile;
  String? _uploadedImageUrl;

  @override
  void initState() {
    super.initState();
    _fetchBuildings();
  }

  @override
  void dispose() {
    _floorNumberController.dispose();
    super.dispose();
  }

  Future<void> _fetchBuildings() async {
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('buildings')
          .select('id, name, lat, lng')
          .eq('is_active', true)
          .order('name');
      if (!mounted) return;
      setState(() {
        _buildings = res as List;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Failed to load buildings: $e');
    }
  }

  /// Looks up the `building_floors` row for the typed floor number, creating
  /// it if it doesn't exist yet.
  Future<void> _onFloorNumberChanged(int floorNumber) async {
    setState(() {
      _floorNumber = floorNumber;
      _selectedFloor = null;
      _selectedImageFile = null;
      _uploadedImageUrl = null;
    });

    if (_selectedBuilding == null) return;

    try {
      final res = await Supabase.instance.client
          .from('building_floors')
          .select(
              'id, floor_number, image_url, is_georeferenced, reference_points')
          .eq('building_id', _selectedBuilding['id'])
          .eq('floor_number', floorNumber)
          .eq('is_active', true)
          .maybeSingle();

      Map<String, dynamic> floor;
      if (res != null) {
        floor = Map<String, dynamic>.from(res);
        debugPrint('✅ Floor found: $floorNumber');
      } else {
        debugPrint('⚠️ Floor $floorNumber not found. Creating…');
        final inserted = await Supabase.instance.client
            .from('building_floors')
            .insert({
              'building_id': _selectedBuilding['id'],
              'floor_number': floorNumber,
              'is_active': true,
              'image_url': '',
              'is_georeferenced': false,
              'reference_points': [],
            })
            .select()
            .single();
        floor = Map<String, dynamic>.from(inserted);
        debugPrint('✅ Floor created: $floorNumber');
      }
      floor['reference_points'] = floor['reference_points'] ?? [];

      // Ignore a stale response if the user typed a new number meanwhile.
      if (!mounted || _floorNumber != floorNumber) return;
      setState(() => _selectedFloor = floor);
    } catch (e) {
      debugPrint('Floor error: $e');
      _showError('Error loading floor: $e');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 90,
      );
      if (image == null) return;

      setState(() {
        _selectedImageFile = File(image.path);
        _isUploading = true;
      });

      final bytes = await image.readAsBytes();
      final buildingId = _selectedBuilding['id'].toString();
      final floorNum = _selectedFloor['floor_number'].toString();
      final fileName =
          'floor_b${buildingId}_f${floorNum}_'
          '${DateTime.now().millisecondsSinceEpoch}.jpg';

      await Supabase.instance.client.storage.from('floor-plans').uploadBinary(
            fileName,
            bytes,
            fileOptions:
                const FileOptions(contentType: 'image/jpeg', upsert: true),
          );

      final url = Supabase.instance.client.storage
          .from('floor-plans')
          .getPublicUrl(fileName);

      await Supabase.instance.client
          .from('building_floors')
          .update({'image_url': url}).eq('id', _selectedFloor['id']);

      if (!mounted) return;
      setState(() {
        _uploadedImageUrl = url;
        _selectedFloor['image_url'] = url;
        _isUploading = false;
      });
      _showSuccess('✅ Floor plan uploaded successfully!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      _showError('Upload failed: $e');
    }
  }

  bool _hasFloorPlan() {
    if (_selectedFloor == null || _floorNumber == null) return false;
    final url = _uploadedImageUrl ?? _selectedFloor['image_url'];
    return url != null && (url as String).isNotEmpty;
  }

  void _showUploadOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Replace Floor Plan',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A))),
              const SizedBox(height: 16),
              _sheetTile(
                Icons.photo_library_outlined,
                'Choose from Gallery',
                'Select an existing floor plan image',
                () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 8),
              _sheetTile(
                Icons.camera_alt_outlined,
                'Take a Photo',
                'Photograph the floor plan',
                () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetTile(
      IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF5E6E6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF7B1C1C)),
      ),
      title: Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B))),
      onTap: onTap,
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message), backgroundColor: const Color(0xFF7B1C1C)),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF1D9E75),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F4F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B1C1C),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Floor Plan Georeferencing',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            Text('⚠️ Temporary Tool',
                style: TextStyle(color: Color(0xFFC9972C), fontSize: 10)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF7B1C1C)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Warning banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFC9972C)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFC9972C), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Temporary georeferencing tool. Remove after data '
                            'collection.',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF633806)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Building + Floor selector
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Select Location',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF7B1C1C))),
                        const SizedBox(height: 16),
                        const Text('Building',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF6B6B6B))),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<dynamic>(
                          initialValue: _selectedBuilding,
                          hint: const Text('Select building'),
                          isExpanded: true,
                          decoration: _fieldDeco,
                          items: _buildings
                              .map((b) => DropdownMenuItem<dynamic>(
                                    value: b,
                                    child: Text('${b['name']}',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedBuilding = val;
                              _selectedFloor = null;
                              _floorNumber = null;
                              _floorNumberController.clear();
                              _selectedImageFile = null;
                              _uploadedImageUrl = null;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        const Text('Floor Number',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF6B6B6B))),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _floorNumberController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'e.g. 1, 2, 3, 4',
                            helperText: 'Enter the floor number',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          onChanged: (val) {
                            final n = int.tryParse(val.trim());
                            if (n != null) {
                              _onFloorNumberChanged(n);
                            } else {
                              setState(() {
                                _floorNumber = null;
                                _selectedFloor = null;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_selectedFloor != null) _buildUploadSection(),
                  const SizedBox(height: 12),

                  if (_selectedFloor != null) _buildFloorStatusCard(),
                  const SizedBox(height: 16),

                  if (_selectedFloor != null &&
                      _floorNumber != null &&
                      _hasFloorPlan())
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FloorPlanGeoScreen(
                                building: _selectedBuilding,
                                floor: _selectedFloor,
                              ),
                            ),
                          ).then((_) {
                            // Refresh floor data when coming back.
                            if (_selectedBuilding != null &&
                                _floorNumber != null) {
                              _onFloorNumberChanged(_floorNumber!);
                            }
                          });
                        },
                        icon: const Icon(Icons.map_outlined,
                            color: Color(0xFFC9972C)),
                        label: const Text('Start Georeferencing →',
                            style: TextStyle(
                                color: Color(0xFFC9972C),
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B1C1C),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildUploadSection() {
    final existingUrl = _selectedFloor?['image_url'] as String?;
    final hasExisting = existingUrl != null && existingUrl.isNotEmpty;
    final displayUrl =
        _uploadedImageUrl ?? (hasExisting ? existingUrl : null);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.image_outlined,
                  color: Color(0xFF7B1C1C), size: 18),
              const SizedBox(width: 8),
              const Text('Floor Plan Image',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7B1C1C))),
              const Spacer(),
              if (displayUrl != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5F0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Uploaded ✅',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF1D9E75),
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Has an image → preview + replace
          if (displayUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _selectedImageFile != null
                  ? Image.file(_selectedImageFile!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.contain)
                  : Image.network(
                      displayUrl,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          height: 200,
                          color: const Color(0xFFF5F5F5),
                          child: const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF7B1C1C)),
                          ),
                        );
                      },
                      errorBuilder: (ctx, e, s) => Container(
                        height: 200,
                        color: const Color(0xFFF5F5F5),
                        child: Center(
                          child: Icon(Icons.broken_image,
                              color: Colors.grey[400], size: 48),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isUploading ? null : _showUploadOptions,
                icon: const Icon(Icons.refresh,
                    color: Color(0xFF7B1C1C), size: 16),
                label: const Text('Replace Floor Plan',
                    style: TextStyle(color: Color(0xFF7B1C1C), fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF7B1C1C)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],

          // No image yet → upload buttons / progress
          if (displayUrl == null) ...[
            if (_isUploading)
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF7B1C1C)),
                      SizedBox(height: 12),
                      Text('Uploading floor plan…',
                          style: TextStyle(
                              color: Color(0xFF6B6B6B), fontSize: 13)),
                    ],
                  ),
                ),
              )
            else ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined,
                      color: Color(0xFFC9972C)),
                  label: const Text('📁 Choose from Gallery',
                      style: TextStyle(
                          color: Color(0xFFC9972C),
                          fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7B1C1C),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined,
                      color: Color(0xFF7B1C1C)),
                  label: const Text('📷 Take a Photo',
                      style: TextStyle(
                          color: Color(0xFF7B1C1C),
                          fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF7B1C1C)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Upload a clear image of the floor plan',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildFloorStatusCard() {
    final isGeoreferenced = _selectedFloor['is_georeferenced'] == true;
    final points = (_selectedFloor['reference_points'] as List?) ?? [];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Floor Status',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF7B1C1C))),
          const SizedBox(height: 12),
          _statusRow('Floor Plan Uploaded', _hasFloorPlan()),
          const SizedBox(height: 8),
          _statusRow('Georeferenced', isGeoreferenced),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on,
                  size: 16, color: Color(0xFF6B6B6B)),
              const SizedBox(width: 8),
              const Text('Reference Points: ',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B6B6B))),
              Text('${points.length}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: points.length >= 3
                          ? const Color(0xFF1D9E75)
                          : const Color(0xFF7B1C1C))),
              Text(
                points.length >= 3 ? ' ✅ Ready to save' : ' (min 3 needed)',
                style: TextStyle(
                    fontSize: 11,
                    color: points.length >= 3
                        ? const Color(0xFF1D9E75)
                        : const Color(0xFFC9972C)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusRow(String label, bool done) {
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 16,
          color: done ? const Color(0xFF1D9E75) : Colors.grey[400],
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B))),
      ],
    );
  }

  static Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06), blurRadius: 8),
          ],
        ),
        child: child,
      );

  static final _fieldDeco = InputDecoration(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );
}

// ═══════════════════════════════════════════════════════════════════════
// STEP 3 — floor plan + draggable crosshair + GPS pinning
// ═══════════════════════════════════════════════════════════════════════

class FloorPlanGeoScreen extends StatefulWidget {
  final dynamic building;
  final dynamic floor;

  const FloorPlanGeoScreen({
    super.key,
    required this.building,
    required this.floor,
  });

  @override
  State<FloorPlanGeoScreen> createState() => _FloorPlanGeoScreenState();
}

class _FloorPlanGeoScreenState extends State<FloorPlanGeoScreen> {
  // Reference points list.
  List<Map<String, dynamic>> _referencePoints = [];

  // GPS state.
  bool _isGettingGPS = false;
  bool _isSaving = false;

  // Label for current pinpoint.
  String _selectedLabel = 'Room Entrance';
  final _customLabelController = TextEditingController();

  // Transform controller for InteractiveViewer.
  final _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    // Load existing reference points.
    final points = widget.floor['reference_points'];
    if (points != null && points is List) {
      _referencePoints = List<Map<String, dynamic>>.from(
          points.map((p) => Map<String, dynamic>.from(p as Map)));
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _customLabelController.dispose();
    super.dispose();
  }

  // ── crosshair → floor plan pixel position ──
  //
  // The crosshair is fixed at the centre of the screen — the floor plan
  // moves under it. Inverting the InteractiveViewer's current transform maps
  // that fixed screen point back to floor-plan pixel space.
  Offset _getCrosshairFloorPlanPosition() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return Offset.zero;

    final widgetSize = renderBox.size;

    // Centre of the screen (offset for the bottom panel height).
    final center = Offset(
      widgetSize.width / 2,
      widgetSize.height / 2 - 100,
    );

    final matrix = _transformationController.value;
    final inverseMatrix = Matrix4.inverted(matrix);

    return MatrixUtils.transformPoint(inverseMatrix, center);
  }

  // ── pin current GPS location at the crosshair ──

  Future<void> _pinCurrentLocation() async {
    setState(() => _isGettingGPS = true);

    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _showError('Location permission denied');
        setState(() => _isGettingGPS = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 30),
        ),
      );

      final pixel = _getCrosshairFloorPlanPosition();

      final label = _selectedLabel == 'Other'
          ? (_customLabelController.text.trim().isEmpty
              ? 'Custom Point'
              : _customLabelController.text.trim())
          : _selectedLabel;

      final point = {
        'label': label,
        'pixel_x': pixel.dx,
        'pixel_y': pixel.dy,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
        'timestamp': DateTime.now().toIso8601String(),
      };

      setState(() {
        _referencePoints.add(point);
        _isGettingGPS = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📍 Pinned: $label',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.white)),
                Text(
                  'GPS: ${pos.latitude.toStringAsFixed(6)}, '
                  '${pos.longitude.toStringAsFixed(6)}',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Text(
                  'Accuracy: ${pos.accuracy.toStringAsFixed(1)}m  '
                  'Total: ${_referencePoints.length} points',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1D9E75),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() => _isGettingGPS = false);
      _showError('GPS error: $e');
    }
  }

  // ── save ──

  Future<void> _saveGeoreferencing() async {
    if (_referencePoints.length < 3) {
      _showError('Add at least 3 points first');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client.from('building_floors').update({
        'reference_points': _referencePoints,
        'is_georeferenced': true,
      }).eq('id', widget.floor['id']);

      setState(() => _isSaving = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Georeferencing saved! '
                '${_referencePoints.length} points saved.'),
            backgroundColor: const Color(0xFF1D9E75),
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      _showError('Save failed: $e');
    }
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B1C1C),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.building['name']} — Floor '
              '${widget.floor['floor_number']}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
            const Text('📍 Georeferencing Mode',
                style: TextStyle(color: Color(0xFFC9972C), fontSize: 10)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _referencePoints.length >= 3
                      ? const Color(0xFF1D9E75)
                      : const Color(0xFFC9972C),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${_referencePoints.length} pts',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildFloorPlanArea()),
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildFloorPlanArea() {
    final imageUrl = widget.floor['image_url'] as String?;

    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        color: const Color(0xFF1A1A1A),
        child: Center(
          child: Text('No floor plan image',
              style: TextStyle(color: Colors.grey[400])),
        ),
      );
    }

    return Stack(
      children: [
        // Floor plan image — moves when dragged; crosshair stays fixed.
        InteractiveViewer(
          transformationController: _transformationController,
          minScale: 0.3,
          maxScale: 10.0,
          boundaryMargin: const EdgeInsets.all(500),
          onInteractionUpdate: (_) => setState(() {}),
          child: Container(
            color: const Color(0xFF1A1A1A),
            child: Center(
              child: Stack(
                children: [
                  Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (ctx, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        width: 400,
                        height: 600,
                        color: const Color(0xFF1A1A1A),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                  color: Color(0xFFC9972C)),
                              const SizedBox(height: 12),
                              Text('Loading floor plan…',
                                  style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                      );
                    },
                    errorBuilder: (ctx, e, s) => Container(
                      width: 400,
                      height: 600,
                      color: const Color(0xFF1A1A1A),
                      child: Center(
                        child: Icon(Icons.broken_image,
                            color: Colors.grey[600], size: 48),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _RefPointsPainter(
                          referencePoints: _referencePoints,
                          transformMatrix: _transformationController.value,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Fixed crosshair in centre — does NOT move with the floor plan.
        const Center(
          child: IgnorePointer(
            child: SizedBox(
              width: 60,
              height: 60,
              child: CustomPaint(painter: _CrosshairPainter()),
            ),
          ),
        ),

        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on,
                    color: Color(0xFFC9972C), size: 14),
                const SizedBox(width: 4),
                Text('${_referencePoints.length} points saved',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),

        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: _showPointsList,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.list, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('View Points',
                      style: TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '① Drag floor plan until crosshair ┼ points at room '
                  'entrance  ② Walk to that room  ③ Press Get GPS & Pin',
                  style: TextStyle(color: Colors.grey[400], fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _selectedLabel,
                decoration: InputDecoration(
                  labelText: 'Point Label',
                  labelStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[700]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[700]!),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                dropdownColor: const Color(0xFF2A2A2A),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                items: const [
                  'Building Entrance',
                  'Room Entrance',
                  'Staircase',
                  'Elevator',
                  'Comfort Room',
                  'Corridor Junction',
                  'Fire Exit',
                  'Other',
                ]
                    .map((label) => DropdownMenuItem(
                          value: label,
                          child: Text(label,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (val) => setState(() => _selectedLabel = val!),
              ),
              const SizedBox(height: 8),
              if (_selectedLabel == 'Other')
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    controller: _customLabelController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Enter custom label',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[700]!),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isGettingGPS ? null : _pinCurrentLocation,
                      icon: _isGettingGPS
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: Color(0xFF7B1C1C), strokeWidth: 2),
                            )
                          : const Icon(Icons.gps_fixed,
                              color: Color(0xFF7B1C1C), size: 18),
                      label: Text(
                        _isGettingGPS ? 'Getting GPS…' : '📍 Get GPS & Pin',
                        style: const TextStyle(
                            color: Color(0xFF7B1C1C),
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC9972C),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _referencePoints.length < 3
                          ? null
                          : (_isSaving ? null : _saveGeoreferencing),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.save,
                              color: Colors.white, size: 16),
                      label: Text(
                        _isSaving
                            ? 'Saving…'
                            : 'Save\n(${_referencePoints.length}/3)',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _referencePoints.length < 3
                            ? Colors.grey[700]
                            : const Color(0xFF1D9E75),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              if (_referencePoints.length < 3)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Need ${3 - _referencePoints.length} more point'
                    '${3 - _referencePoints.length == 1 ? "" : "s"} to save',
                    style:
                        const TextStyle(color: Color(0xFFC9972C), fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPointsList() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => StatefulBuilder(
          builder: (ctx, setModalState) => Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.location_on,
                        color: Color(0xFFC9972C), size: 20),
                    const SizedBox(width: 8),
                    Text('Reference Points (${_referencePoints.length})',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _referencePoints.length >= 3
                            ? const Color(0xFF1D9E75)
                            : const Color(0xFFC9972C),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _referencePoints.length >= 3
                            ? '✅ Ready'
                            : '${3 - _referencePoints.length} more',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: Colors.grey[800]),
              Expanded(
                child: _referencePoints.isEmpty
                    ? Center(
                        child: Text(
                          'No points yet.\nAdd at least 3 points.',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _referencePoints.length,
                        separatorBuilder: (_, _) =>
                            Divider(color: Colors.grey[800], height: 1),
                        itemBuilder: (_, i) {
                          final p = _referencePoints[i];
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 4),
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: const Color(0xFFC9972C),
                              child: Text('${i + 1}',
                                  style: const TextStyle(
                                      color: Color(0xFF7B1C1C),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ),
                            title: Text('${p['label'] ?? 'Point ${i + 1}'}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                            subtitle: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'GPS: '
                                  '${(p['lat'] as num).toStringAsFixed(6)}, '
                                  '${(p['lng'] as num).toStringAsFixed(6)}',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 10),
                                ),
                                Text(
                                  'Accuracy: '
                                  '${(p['accuracy'] as num).toStringAsFixed(1)}m',
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 10),
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: Colors.red[400], size: 20),
                              onPressed: () {
                                setState(() {
                                  _referencePoints.removeAt(i);
                                });
                                setModalState(() {});
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message), backgroundColor: const Color(0xFF7B1C1C)),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC9972C)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawLine(
        Offset(0, center.dy), Offset(size.width, center.dy), paint);
    canvas.drawLine(
        Offset(center.dx, 0), Offset(center.dx, size.height), paint);
    canvas.drawCircle(center, 4, paint);

    const cornerSize = 8.0;
    const gap = 12.0;

    // Top-left corner.
    canvas.drawLine(Offset(center.dx - gap - cornerSize, center.dy - gap),
        Offset(center.dx - gap, center.dy - gap), paint);
    canvas.drawLine(Offset(center.dx - gap, center.dy - gap - cornerSize),
        Offset(center.dx - gap, center.dy - gap), paint);

    // Top-right corner.
    canvas.drawLine(Offset(center.dx + gap, center.dy - gap),
        Offset(center.dx + gap + cornerSize, center.dy - gap), paint);
    canvas.drawLine(Offset(center.dx + gap, center.dy - gap - cornerSize),
        Offset(center.dx + gap, center.dy - gap), paint);

    // Bottom-left corner.
    canvas.drawLine(Offset(center.dx - gap - cornerSize, center.dy + gap),
        Offset(center.dx - gap, center.dy + gap), paint);
    canvas.drawLine(Offset(center.dx - gap, center.dy + gap),
        Offset(center.dx - gap, center.dy + gap + cornerSize), paint);

    // Bottom-right corner.
    canvas.drawLine(Offset(center.dx + gap, center.dy + gap),
        Offset(center.dx + gap + cornerSize, center.dy + gap), paint);
    canvas.drawLine(Offset(center.dx + gap, center.dy + gap),
        Offset(center.dx + gap, center.dy + gap + cornerSize), paint);
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) => false;
}

class _RefPointsPainter extends CustomPainter {
  final List<Map<String, dynamic>> referencePoints;
  final Matrix4 transformMatrix;

  _RefPointsPainter({
    required this.referencePoints,
    required this.transformMatrix,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < referencePoints.length; i++) {
      final p = referencePoints[i];
      final px = (p['pixel_x'] as num).toDouble();
      final py = (p['pixel_y'] as num).toDouble();

      final transformed =
          MatrixUtils.transformPoint(transformMatrix, Offset(px, py));

      canvas.drawCircle(
          transformed, 7, Paint()..color = Colors.white);
      canvas.drawCircle(
          transformed, 5, Paint()..color = const Color(0xFFC9972C));

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
              color: Color(0xFF7B1C1C),
              fontSize: 8,
              fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(transformed.dx - textPainter.width / 2,
            transformed.dy - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_RefPointsPainter old) =>
      old.referencePoints != referencePoints ||
      old.transformMatrix != transformMatrix;
}
