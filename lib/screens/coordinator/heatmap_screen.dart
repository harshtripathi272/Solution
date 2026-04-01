import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../config/theme.dart';
import '../../models/heatmap_point.dart';
import '../../services/heatmap_api_service.dart';

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen>
    with AutomaticKeepAliveClientMixin {
  late HeatmapApiService _apiService;
  late MapController _mapController;
  
  // Filter states
  String? _selectedRegion;
  String? _selectedNeedType;
  double _minSeverity = 0.1;
  String _timeRange = '30d';
  
  // UI state
  List<HeatmapPoint> _heatmapData = [];
  bool _isLoading = false;
  String? _error;
  late Timer _refreshTimer;
  final bool _isAutoRefreshEnabled = true;

  final List<String> _regions = [
    'bihar',
    'jharkhand',
    'assam',
    'bundelkhand',
    'marathwada',
  ];

  final List<String> _needTypes = [
    'water_sanitation',
    'food_security',
    'medical',
    'shelter',
    'education',
    'other',
  ];

  final List<String> _timeRanges = ['7d', '30d', '90d'];

  final Map<String, LatLng> _regionCentres = const {
    'bihar': LatLng(25.0961, 85.3131),
    'jharkhand': LatLng(23.6102, 85.2799),
    'assam': LatLng(26.2006, 92.9376),
    'bundelkhand': LatLng(25.5000, 79.5000),
    'marathwada': LatLng(19.7515, 75.7139),
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _apiService = HeatmapApiService();
    _mapController = MapController();
    _loadHeatmapData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_isAutoRefreshEnabled && mounted) {
        _loadHeatmapData();
      }
    });
  }

  Future<void> _loadHeatmapData() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await _apiService.fetchHeatmapData(
        region: _selectedRegion,
        needType: _selectedNeedType,
        minSeverity: _minSeverity,
        timeRange: _timeRange,
      );

      if (mounted) {
        setState(() {
          _heatmapData = data;
          _isLoading = false;
        });
        _fitMapToData();
      }
    } on HeatmapException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showFilterPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        var draftRegion = _selectedRegion;
        var draftNeedType = _selectedNeedType;
        var draftMinSeverity = _minSeverity;
        var draftTimeRange = _timeRange;

        return StatefulBuilder(
          builder: (context, setBottomSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(32),
                boxShadow: AppDecorations.ambientShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                  child: DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: 0.75,
                    minChildSize: 0.3,
                    maxChildSize: 0.95,
                    builder: (context, scrollController) => SingleChildScrollView(
                      controller: scrollController,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 48,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppColors.outlineVariant,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            Text('Refine View',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ).animate().fadeIn().slideY(begin: 0.1, curve: Curves.easeOutBack),
                            const SizedBox(height: 24),

                            Text('Region Focus', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.outline)),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: draftRegion,
                                  hint: const Text('All Regions'),
                                  items: [null, ..._regions]
                                      .map((region) => DropdownMenuItem(
                                            value: region,
                                            child: Text(region?.toUpperCase() ?? 'All Regions'),
                                          ))
                                      .toList(),
                                  onChanged: (value) {
                                    setBottomSheetState(() => draftRegion = value);
                                  },
                                ),
                              ),
                            ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),
                            const SizedBox(height: 24),

                            Text('Need Category', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.outline)),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _needTypes.map((type) {
                                final isSelected = draftNeedType == type;
                                final idx = _needTypes.indexOf(type);
                                return AnimatedContainer(
                                  duration: 300.ms,
                                  curve: Curves.easeOutCirc,
                                  child: ChoiceChip(
                                    label: Text(type.replaceAll('_', ' ').toUpperCase()),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setBottomSheetState(() {
                                        draftNeedType = selected ? type : null;
                                      });
                                    },
                                    backgroundColor: AppColors.surfaceContainerLow,
                                    selectedColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                      color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                                  ),
                                ).animate().fadeIn(delay: (150 + idx * 50).ms).scaleXY(begin: 0.9, curve: Curves.easeOutBack);
                              }).toList(),
                            ),
                            const SizedBox(height: 32),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Minimum Urgency', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.outline)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: AppDecorations.activeChip.copyWith(color: AppColors.error),
                                  child: Text(
                                    (draftMinSeverity * 10).toStringAsFixed(1),
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
                            const SizedBox(height: 8),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: AppColors.error,
                                inactiveTrackColor: AppColors.surfaceContainerHigh,
                                thumbColor: AppColors.error,
                                overlayColor: AppColors.error.withValues(alpha: 0.2),
                                trackHeight: 8.0,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14.0),
                              ),
                              child: Slider(
                                value: draftMinSeverity,
                                min: 0.0,
                                max: 1.0,
                                divisions: 20,
                                onChanged: (value) {
                                  setBottomSheetState(() => draftMinSeverity = value);
                                },
                              ),
                            ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.1),
                            const SizedBox(height: 32),

                            Text('Time Range', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.outline)),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              children: _timeRanges.asMap().entries.map<Widget>((entry) {
                                final isSelected = draftTimeRange == entry.value;
                                return InputChip(
                                  label: Text(entry.value),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    if (!selected) return;
                                    setBottomSheetState(() => draftTimeRange = entry.value);
                                  },
                                  backgroundColor: AppColors.surfaceContainerLow,
                                  selectedColor: AppColors.tertiary,
                                  labelStyle: TextStyle(
                                    color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
                                  ),
                                  side: BorderSide.none,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ).animate().fadeIn(delay: (400 + entry.key * 50).ms).scaleXY(begin: 0.9, curve: Curves.easeOutBack);
                              }).toList(),
                            ),
                            const SizedBox(height: 48),

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _selectedRegion = draftRegion;
                                    _selectedNeedType = draftNeedType;
                                    _minSeverity = draftMinSeverity;
                                    _timeRange = draftTimeRange;
                                  });
                                  Navigator.pop(context);
                                  _loadHeatmapData();
                                },
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                ),
                                child: const Text('Apply Target Filters', style: TextStyle(fontSize: 16)),
                              ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<WeightedLatLng> _transformToHeatmapDataPoints() {
    final validPoints = _heatmapData.where((point) {
      // Filter out invalid coordinates
      return point.latitude != 0.0 && 
             point.longitude != 0.0 &&
             point.latitude >= -90 && point.latitude <= 90 &&
             point.longitude >= -180 && point.longitude <= 180 &&
             point.weightedIntensity > 0.0;
    }).toList();
    
    return validPoints.map((point) {
      return WeightedLatLng(
        LatLng(point.latitude, point.longitude),
        point.weightedIntensity,
      );
    }).toList();
  }

  Map<String, int> _buildRegionClusterCounts() {
    final counts = <String, int>{
      for (final region in _regions) region: 0,
    };

    for (final point in _heatmapData) {
      final inferred = _inferRegionFromPoint(point);
      if (inferred != null && counts.containsKey(inferred)) {
        counts[inferred] = (counts[inferred] ?? 0) + 1;
      }
    }

    return counts;
  }

  String? _inferRegionFromPoint(HeatmapPoint point) {
    String? bestRegion;
    double? bestDistance;

    for (final entry in _regionCentres.entries) {
      final dLat = (point.latitude - entry.value.latitude).abs();
      final dLon = (point.longitude - entry.value.longitude).abs();

      // Keep the same coarse matching window used by backend region filtering.
      if (dLat > 4.5 || dLon > 4.5) {
        continue;
      }

      final distance = (dLat * dLat) + (dLon * dLon);
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestRegion = entry.key;
      }
    }

    return bestRegion;
  }

  void _fitMapToData() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (_heatmapData.isEmpty) return;

      if (_heatmapData.length == 1) {
        final point = _heatmapData.first;
        _mapController.move(LatLng(point.latitude, point.longitude), 8.0);
        return;
      }

      final dataBounds = LatLngBounds.fromPoints(
        _heatmapData
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList(),
      );

      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: dataBounds,
          padding: const EdgeInsets.all(36),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final clusterCounts = _buildRegionClusterCounts();

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const Icon(Icons.error_outline, size: 64, color: Colors.red),
                   const SizedBox(height: 16),
                   Text(_error!, textAlign: TextAlign.center),
                   const SizedBox(height: 16),
                   ElevatedButton(
                     onPressed: _loadHeatmapData,
                     child: const Text('Retry'),
                   ),
                ],
              ),
            )
          : Stack(
              children: [
                // Map base
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(20.5937, 78.9629), // India center
                    initialZoom: 5.0,
                    minZoom: 4.0,
                    maxZoom: 18.0,
                  ),
                  children: [
                    // OpenStreetMap tiles
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.app',
                    ),
                    
                    // Heatmap layer
                    if (_heatmapData.isNotEmpty)
                      HeatMapLayer(
                        heatMapDataSource: InMemoryHeatMapDataSource(
                          data: _transformToHeatmapDataPoints(),
                        ),
                        heatMapOptions: HeatMapOptions(
                          radius: 56,
                          blurFactor: 0.35,
                          minOpacity: 0.55,
                          gradient: {
                            0.10: Colors.blue,
                            0.30: Colors.cyan,
                            0.50: Colors.green,
                            0.70: Colors.yellow,
                            0.85: Colors.orange,
                            1.00: Colors.red,
                          },
                        ),
                      ),
                      
                    // Pulsing Radar Location
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: const LatLng(20.5937, 78.9629),
                          width: 80,
                          height: 80,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primary.withValues(alpha: 0.2),
                                ),
                              ).animate(onPlay: (controller) => controller.repeat())
                               .scale(begin: const Offset(0.3, 0.3), end: const Offset(1, 1), duration: 2.seconds)
                               .fadeOut(duration: 2.seconds),
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primary,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Floating Glass Header
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 16, 24, 16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest.withValues(alpha: 0.8),
                          border: Border(bottom: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.2))),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('SevaSetu Map', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.refresh, color: AppColors.primary),
                                  onPressed: _loadHeatmapData,
                                ).animate(target: _isLoading ? 1 : 0).rotate(duration: 1.seconds),
                                const SizedBox(width: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.filter_list, color: AppColors.onPrimaryContainer),
                                    onPressed: _showFilterPanel,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ).animate().slideY(begin: -1, duration: 400.ms, curve: Curves.easeOutBack),
                ),

                // Loading overlay
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black26,
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ),

                // Severity legend (Glassmorphic)
                Positioned(
                  bottom: 24,
                  right: 24,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest.withValues(alpha: 0.75),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Severity', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            _legendItem('Extreme', Colors.red),
                            _legendItem('Severe', Colors.orange),
                            _legendItem('Moderate', Colors.yellow),
                            _legendItem('Stressed', Colors.green),
                            _legendItem('Minimal', Colors.blue),
                          ],
                        ),
                      ),
                    ),
                  ).animate().slideX(begin: 1, duration: 600.ms, curve: Curves.easeOutBack),
                ),

                // Data summary (Glassmorphic)
                Positioned(
                  bottom: 24,
                  left: 24,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest.withValues(alpha: 0.75),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Clusters', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Text(
                              'Total: ${_heatmapData.length}',
                              style: theme.textTheme.labelMedium?.copyWith(color: AppColors.primary),
                            ),
                            const SizedBox(height: 12),
                            ..._regions.map((region) {
                              final count = clusterCounts[region] ?? 0;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '${region.toUpperCase()}: $count',
                                  style: theme.textTheme.labelSmall?.copyWith(color: AppColors.onSurfaceVariant),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ).animate().slideX(begin: -1, duration: 600.ms, curve: Curves.easeOutBack),
                ),
              ],
            ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }

}
