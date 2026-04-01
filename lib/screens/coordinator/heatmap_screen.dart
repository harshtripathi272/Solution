import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:latlong2/latlong.dart';
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
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.outline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('Filter Heatmap',
                        style: Theme.of(context).textTheme.displaySmall),
                      const SizedBox(height: 24),

                      Text('Region', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      DropdownButton<String>(
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
                      const SizedBox(height: 24),

                      Text('Need Type', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _needTypes.map((type) {
                          final isSelected = draftNeedType == type;
                          return ChoiceChip(
                            label: Text(type.replaceAll('_', ' ').toUpperCase()),
                            selected: isSelected,
                            onSelected: (selected) {
                              setBottomSheetState(() {
                                draftNeedType = selected ? type : null;
                              });
                            },
                            backgroundColor: AppColors.primaryContainer,
                            selectedColor: AppColors.primary,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),

                      Text(
                        'Minimum Severity: ${(draftMinSeverity * 100).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Slider(
                        value: draftMinSeverity,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        label: draftMinSeverity.toStringAsFixed(2),
                        onChanged: (value) {
                          setBottomSheetState(() => draftMinSeverity = value);
                        },
                      ),
                      const SizedBox(height: 24),

                      Text('Time Range', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: _timeRanges.map((range) {
                          final isSelected = draftTimeRange == range;
                          return FilterChip(
                            label: Text(range),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (!selected) return;
                              setBottomSheetState(() => draftTimeRange = range);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),

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
                          child: const Text('Apply Filters'),
                        ),
                      ),
                      const SizedBox(height: 8),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () async {
                            await _apiService.clearCache();
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Cache cleared')),
                            );
                          },
                          child: const Text('Clear Cache'),
                        ),
                      ),
                    ],
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
      appBar: AppBar(
        title: const Text('SevaSetu Needs Map'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHeatmapData,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterPanel,
          ),
        ],
      ),
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
                  ],
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

                // Severity legend
                Positioned(
                  bottom: 24,
                  right: 24,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Severity', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 12),
                        _legendItem('Extreme', Colors.red),
                        _legendItem('Severe', Colors.orange),
                        _legendItem('Moderate', Colors.yellow),
                        _legendItem('Stressed', Colors.green),
                        _legendItem('Minimal', Colors.blue),
                      ],
                    ),
                  ),
                ),

                // Data summary
                Positioned(
                  bottom: 24,
                  left: 24,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Clusters', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 8),
                        Text(
                          'Total: ${_heatmapData.length}',
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(height: 8),
                        ..._regions.map((region) {
                          final count = clusterCounts[region] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '${region.toUpperCase()}: $count',
                              style: theme.textTheme.labelSmall,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
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
