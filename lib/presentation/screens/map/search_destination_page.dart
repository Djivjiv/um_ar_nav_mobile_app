import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Full-screen destination search. Pushed as a `fullscreenDialog` route so it
/// covers the map, the floating search bar and everything else. Pops the
/// selected destination `Map` back to the route planner.
class SearchDestinationPage extends StatefulWidget {
  final List<Map<String, dynamic>> destinations;

  const SearchDestinationPage({
    super.key,
    required this.destinations,
  });

  @override
  State<SearchDestinationPage> createState() => _SearchDestinationPageState();
}

class _SearchDestinationPageState extends State<SearchDestinationPage> {
  List<Map<String, dynamic>> _filtered = [];
  String _activeFilter = 'all';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = widget.destinations;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filter(String query) {
    setState(() {
      final base = _activeFilter == 'all'
          ? widget.destinations
          : widget.destinations
              .where((d) => d['type'] == _activeFilter)
              .toList();
      _filtered = query.trim().isEmpty
          ? base
          : base.where((d) {
              final name = (d['name'] as String).toLowerCase();
              final sub = (d['subtitle'] as String).toLowerCase();
              final q = query.toLowerCase();
              return name.contains(q) || sub.contains(q);
            }).toList();
    });
  }

  void _setFilter(String type) {
    setState(() => _activeFilter = type);
    _filter(_searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryMaroon,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: const InputDecoration(
            hintText: 'Search buildings, rooms, facilities...',
            hintStyle: TextStyle(color: Colors.white60, fontSize: 14),
            border: InputBorder.none,
          ),
          onChanged: _filter,
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white70),
              onPressed: () {
                _searchController.clear();
                _filter('');
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('All', 'all'),
                  const SizedBox(width: 8),
                  _chip('Buildings', 'building'),
                  const SizedBox(width: 8),
                  _chip('Rooms', 'room'),
                  const SizedBox(width: 8),
                  _chip('Facilities', 'facility'),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_filtered.length} results',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF6B6B6B)),
              ),
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off,
                            size: 56, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('No results found',
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('Try a different search',
                            style: TextStyle(
                                color: Colors.grey[400], fontSize: 13)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: Colors.grey[100]),
                    itemBuilder: (ctx, i) {
                      final d = _filtered[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: (d['color'] as Color)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(d['icon'] as IconData,
                              color: d['color'] as Color, size: 22),
                        ),
                        title: Text(
                          d['name'] as String,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1A1A1A)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          d['subtitle'] as String,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF6B6B6B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _typePill(d['type'] as String),
                        onTap: () => Navigator.of(context).pop(d),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String type) {
    final isActive = _activeFilter == type;
    return GestureDetector(
      onTap: () => _setFilter(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryMaroon
              : const Color(0xFFF8F4F0),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isActive
                  ? AppColors.primaryMaroon
                  : const Color(0xFFD9C9B0)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? Colors.white : const Color(0xFF6B6B6B),
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _typePill(String type) {
    final color = type == 'building'
        ? AppColors.primaryMaroon
        : type == 'room'
            ? const Color(0xFF185FA5)
            : AppColors.accentGold;
    final bg = type == 'building'
        ? const Color(0xFFF5E6E6)
        : type == 'room'
            ? const Color(0xFFE6EEF9)
            : const Color(0xFFFFF8E7);
    final label = type == 'building'
        ? 'Building'
        : type == 'room'
            ? 'Room'
            : 'Facility';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}
