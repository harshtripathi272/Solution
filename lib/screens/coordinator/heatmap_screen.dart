import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:latlong2/latlong.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';
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
  Set<String> _selectedNeedTypes = {};
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
        needType: _selectedNeedTypes.isNotEmpty ? _selectedNeedTypes.first : null,
        minSeverity: _minSeverity,
        timeRange: _timeRange,
      );

      if (mounted) {
        setState(() {
          _heatmapData = data;
          _isLoading = false;
        });
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
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
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
                  
                  // Region filter
                  Text('Region', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedRegion,
                    hint: const Text('All Regions'),
                    items: [null, ..._regions]
                        .map((region) => DropdownMenuItem(
                          value: region,
                          child: Text(region?.toUpperCase() ?? 'All Regions'),
                        ))
                        .toList(),
                    onChanged: (value) {
                      setState(() => _selectedRegion = value);
                      Navigator.pop(context);
                      _loadHeatmapData();
                    },
                  ),
                  const SizedBox(height: 24),
                  
                  // Need types filter
                  Text('Need Types', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  MultiSelectChipField(
                    items: _needTypes
                        .map((type) => MultiSelectItem(type, type.replaceAll('_', ' ').toUpperCase()))
                        .toList(),
                    initialValue: _selectedNeedTypes.toList(),
                    onTap: (selectedItems) {
                      setState(() => _selectedNeedTypes = selectedItems.cast<String>().toSet());
                    },
                    chipColor: AppColors.primaryContainer,
                    selectedChipColor: AppColors.primary,
                    textStyle: const TextStyle(color: Colors.black87),
                  ),
                  const SizedBox(height: 24),
                  
                  // Severity slider
                  Text('Minimum Severity: ${(_minSeverity * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Slider(
                    value: _minSeverity,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    onChanged: (value) => setState(() => _minSeverity = value),
                    onChangeEnd: (_) => _loadHeatmapData(),
                  ),
                  const SizedBox(height: 24),
                  
                  // Time range filter
                  Text('Time Range', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: _timeRanges.map((range) {
                      final isSelected = _timeRange == range;
                      return FilterChip(
                        label: Text(range),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _timeRange = range);
                            Navigator.pop(context);
                            _loadHeatmapData();
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  
                  // Clear cache button
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
  }

  List<WeightedLatLng> _transformToHeatmapDataPoints() {
    return _heatmapData.map((point) {
      return WeightedLatLng(
        LatLng(point.latitude, point.longitude),
        point.weightedIntensity,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final highSeverityPoints = _heatmapData.where((p) => p.severity > 0.7).toList();

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
                          radius: 25,
                          blurFactor: 0.6,
                          minOpacity: 0.3,
                          gradient: {
                            0.2: Colors.blue,
                            0.4: Colors.green,
                            0.6: Colors.yellow,
                            0.8: Colors.orange,
                            1.0: Colors.red,
                          },
                        ),
                      ),
                    
                    // High severity markers
                    if (highSeverityPoints.isNotEmpty)
                      MarkerLayer(
                        markers: highSeverityPoints.map((point) {
                          return Marker(
                            point: LatLng(point.latitude, point.longitude),
                            width: 40,
                            height: 40,
                            child: GestureDetector(
                              onTap: () => _showPointDetails(point),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.red.withValues(alpha: 0.8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    point.populationAffected > 999
                                        ? '${(point.populationAffected / 1000).toStringAsFixed(0)}k'
                                        : point.populationAffected.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
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
                        Text(
                          'Clusters: ${_heatmapData.length}',
                          style: theme.textTheme.labelLarge,
                        ),
                        Text(
                          'High Severity: ${highSeverityPoints.length}',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Auto-refresh: ${_isAutoRefreshEnabled ? 'ON' : 'OFF'}',
                          style: theme.textTheme.labelSmall,
                        ),
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

  void _showPointDetails(HeatmapPoint point) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getSeverityColor(point.severity),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.location_on, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Geohash: ${point.geohash}',
                        style: Theme.of(context).textTheme.titleMedium),
                      Text(point.severityLabel,
                        style: Theme.of(context).textTheme.labelMedium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _detailRow('Severity', '${(point.severity * 100).toStringAsFixed(1)}%'),
            _detailRow('Population Affected', point.populationAffected.toString()),
            _detailRow('Confidence', '${(point.confidence * 100).toStringAsFixed(0)}%'),
            _detailRow('Need Type', point.needType.replaceAll('_', ' ')),
            _detailRow('Source Count', point.sourceCount.toString()),
            const SizedBox(height: 24),
            if (point.needTypeBreakdown.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Need Breakdown', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  ...point.needTypeBreakdown.entries.map((e) =>
                    _detailRow(e.key.replaceAll('_', ' '), e.value.toString())),
                ],
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          )),
        ],
      ),
    );
  }

  Color _getSeverityColor(double severity) {
    if (severity >= 0.8) return Colors.red;
    if (severity >= 0.6) return Colors.orange;
    if (severity >= 0.4) return Colors.yellow;
    if (severity >= 0.2) return Colors.green;
    return Colors.blue;
  }
}
