import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme.dart';
import '../../models/community_graph_models.dart';
import '../../services/community_graph_api_service.dart';
import 'community_detail_screen.dart';
import 'heatmap_screen.dart';

class CommunityGraphScreen extends StatefulWidget {
  const CommunityGraphScreen({super.key});

  @override
  State<CommunityGraphScreen> createState() => _CommunityGraphScreenState();
}

class _CommunityGraphScreenState extends State<CommunityGraphScreen> {
  final CommunityGraphApiService _service = CommunityGraphApiService();

  CommunityGraphOverview? _overview;
  bool _loading = true;
  String? _error;
  double _timeWindowDays = 180;
  String? _selectedCommunityId;
  bool _showHeatmap = false; // Toggle for graph/heatmap

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  Future<void> _loadOverview() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final overview = await _service.fetchOverview(limit: 12);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _selectedCommunityId = overview.profiles.isNotEmpty
            ? overview.profiles.first.id
            : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<CommunityProfile> get _visibleProfiles {
    final profiles = _overview?.profiles ?? const [];
    return profiles.where((profile) {
      final visible = profile.lastVerifiedAt ?? profile.updatedAt;
      if (visible == null) {
        return true;
      }
      return DateTime.now().difference(visible).inDays <= _timeWindowDays;
    }).toList();
  }

  CommunityProfile? get _selectedProfile {
    final profiles = _visibleProfiles;
    if (profiles.isEmpty) return null;
    final selected = _selectedCommunityId;
    return profiles
            .where((profile) => profile.id == selected)
            .cast<CommunityProfile?>()
            .firstOrNull ??
        profiles.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overview = _overview;
    final visibleProfiles = _visibleProfiles;

    // Show heatmap if toggled
    if (_showHeatmap) {
      return _buildHeatmapView(theme);
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFfbf9f9), Color(0xFFf2efec), Color(0xFFeef4ef)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _buildErrorState(theme)
            : RefreshIndicator(
                onRefresh: _loadOverview,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Visualization toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: _buildHero(theme, overview, visibleProfiles),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _visualizationButton(
                                  icon: Icons.hub,
                                  label: 'Graph',
                                  isSelected: !_showHeatmap,
                                  onPressed: () =>
                                      setState(() => _showHeatmap = false),
                                ),
                                _visualizationButton(
                                  icon: Icons.thermostat,
                                  label: 'Heatmap',
                                  isSelected: _showHeatmap,
                                  onPressed: () =>
                                      setState(() => _showHeatmap = true),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildTimeSlider(theme),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 1100;
                          final graph = _buildGraphPanel(
                            theme,
                            visibleProfiles,
                          );
                          final matrix = _buildMatrixPanel(
                            theme,
                            visibleProfiles,
                          );
                          if (wide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: graph),
                                const SizedBox(width: 20),
                                Expanded(flex: 2, child: matrix),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              graph,
                              const SizedBox(height: 20),
                              matrix,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _buildSelectedCommunityCard(theme),
                      const SizedBox(height: 20),
                      _buildCommunityList(theme),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _visualizationButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.outlineVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.outlineVariant,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeatmapView(ThemeData theme) {
    // Embed the actual HeatmapScreen widget
    return Stack(
      children: [
        const HeatmapScreen(),
        Positioned(
          top: 16,
          left: 16,
          child: SafeArea(
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _showHeatmap = false),
              icon: const Icon(Icons.hub),
              label: const Text('Constellation Map'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.onSurface,
                elevation: 4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Community graph unavailable',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadOverview,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(
    ThemeData theme,
    CommunityGraphOverview? overview,
    List<CommunityProfile> visibleProfiles,
  ) {
    final totalNeeds = visibleProfiles.fold<int>(
      0,
      (sum, profile) => sum + profile.needs.length,
    );
    final staleCount = visibleProfiles
        .where((profile) => profile.isStale)
        .length;
    final gapCount = overview?.coverageGaps.length ?? 0;

    return Container(
          padding: const EdgeInsets.all(24),
          decoration: AppDecorations.baseCard.copyWith(
            gradient: const LinearGradient(
              colors: [Color(0xFF07112f), Color(0xFF10284d), Color(0xFF193a32)],
              stops: [0.0, 0.55, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Community intelligence network',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Constellation map, need matrix, and freshness trail',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _metricChip(
                    'Communities',
                    '${visibleProfiles.length}',
                    Colors.white,
                  ),
                  _metricChip('Need signals', '$totalNeeds', Colors.white),
                  _metricChip('Coverage gaps', '$gapCount', Colors.white),
                  _metricChip('Stale communities', '$staleCount', Colors.white),
                ],
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _metricChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildTimeSlider(ThemeData theme) {
    return Container(
          padding: const EdgeInsets.all(20),
          decoration: AppDecorations.baseCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Temporal validity', style: theme.textTheme.titleLarge),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: AppDecorations.activeChip,
                    child: Text(
                      '${_timeWindowDays.round()} days',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Stale links fade after six months of inactivity. Slide to narrow the network to recent evidence.',
                style: theme.textTheme.bodyMedium,
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: AppColors.surfaceContainerHigh,
                  thumbColor: AppColors.secondary,
                  overlayColor: AppColors.secondary.withValues(alpha: 0.16),
                ),
                child: Slider(
                  value: _timeWindowDays,
                  min: 30,
                  max: 365,
                  divisions: 11,
                  label: '${_timeWindowDays.round()} days',
                  onChanged: (value) =>
                      setState(() => _timeWindowDays = value.roundToDouble()),
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: 120.ms)
        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _buildGraphPanel(ThemeData theme, List<CommunityProfile> profiles) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.baseCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Constellation map',
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: AppDecorations.activeChip,
                child: Text(
                  'force-directed',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AspectRatio(
            aspectRatio: 1.35,
            child: _ForceGraphView(
              profiles: profiles,
              selectedCommunityId: _selectedCommunityId,
              onSelectCommunity: (communityId) =>
                  setState(() => _selectedCommunityId = communityId),
            ),
          ),
          const SizedBox(height: 12),
          _buildLegend(theme),
        ],
      ),
    );
  }

  Widget _buildLegend(ThemeData theme) {
    final entries = [
      ('Nutrition', _needColor('severe_acute_malnutrition')),
      ('WASH', _needColor('wash_deficits')),
      ('Maternal health', _needColor('maternal_health_gaps')),
      ('Infrastructure', _needColor('infrastructure_failures')),
      ('Livelihoods', _needColor('livelihood_threats')),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: entries
          .map(
            (entry) => Chip(
              label: Text(entry.$1),
              avatar: CircleAvatar(radius: 6, backgroundColor: entry.$2),
              backgroundColor: AppColors.surfaceContainerLow,
              side: BorderSide.none,
            ),
          )
          .toList(),
    );
  }

  Widget _buildMatrixPanel(ThemeData theme, List<CommunityProfile> profiles) {
    const categories = [
      ('severe_acute_malnutrition', 'Nutrition'),
      ('wash_deficits', 'WASH'),
      ('maternal_health_gaps', 'Maternal'),
      ('infrastructure_failures', 'Infra'),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.baseCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vulnerability matrix', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            'Villages against nutrition, water, health, and infrastructure severity.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 150),
                    ...categories.map(
                      (category) => SizedBox(
                        width: 88,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: 6,
                            right: 6,
                            bottom: 12,
                          ),
                          child: Text(
                            category.$2,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                ...profiles.map(
                  (profile) =>
                      _MatrixRow(profile: profile, categories: categories),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildMatrixLegend(theme),
        ],
      ),
    );
  }

  Widget _buildMatrixLegend(ThemeData theme) {
    final labels = [
      'Stale cells dim after 180 days',
      'Brighter cells represent stronger chronic scores',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: labels
          .map(
            (label) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $label', style: theme.textTheme.bodySmall),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSelectedCommunityCard(ThemeData theme) {
    final profile = _selectedProfile;
    if (profile == null) {
      return const SizedBox.shrink();
    }

    final needs = profile.needs.take(4).toList();
    final reportUrl =
        (profile.report['url'] ?? profile.provenance['source_url'] ?? '')
            .toString();
    final stale = profile.isStale;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.baseCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      '${profile.region}, ${profile.district} · ${profile.block}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (stale)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'stale',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Active organizations: ${profile.activeOrganizationsLabel}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Last verified: ${profile.lastVerifiedLabel}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: needs
                .map(
                  (need) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _needColor(need.needType).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      '${_humanizeNeed(need.needType)} ${(need.chronicScore * 100).round()}%',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: _needColor(need.needType),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                onPressed: reportUrl.isEmpty
                    ? null
                    : () => _openLink(reportUrl),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Source PDF'),
              ),
              const SizedBox(width: 12),
              if ((profile.coordinationOpportunities.isNotEmpty))
                TextButton.icon(
                  onPressed: () => _showCoordinationNotes(context, profile),
                  icon: const Icon(Icons.group_work),
                  label: const Text('Coordination notes'),
                ),
            ],
          ),
          if (profile.coverageGaps.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Knowledge gaps', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...profile.coverageGaps.map(
              (gap) => Text(
                '• ${gap['reason'] ?? gap['community_name']}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showCoordinationNotes(BuildContext context, CommunityProfile profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Coordination Notes',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...profile.coordinationOpportunities.map((opp) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: AppDecorations.contentBlock,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (opp['type'] != null)
                            Text(
                              opp['type'].toString().toUpperCase(),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          if (opp['description'] != null ||
                              opp['reason'] != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              opp['description']?.toString() ??
                                  opp['reason']?.toString() ??
                                  '',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                          if (opp['communities'] != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Communities: ${(opp['communities'] as List).join(', ')}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  if (profile.similarity.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Similar Communities',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    ...profile.similarity.map(
                      (sim) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: AppDecorations.contentBlock,
                        child: Row(
                          children: [
                            Icon(Icons.hub, size: 16, color: AppColors.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                sim['community_name']?.toString() ??
                                    sim['id']?.toString() ??
                                    'Unknown',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            if (sim['score'] != null)
                              Text(
                                '${((sim['score'] as num).toDouble() * 100).round()}% similar',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCommunityList(ThemeData theme) {
    final selectedId = _selectedCommunityId;
    final profiles = _visibleProfiles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Community cards', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        ...profiles.map((profile) {
          final selected = selectedId == profile.id;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CommunityDetailScreen(profile: profile),
                  ),
                );
                setState(() => _selectedCommunityId = profile.id);
              },
              child: AnimatedContainer(
                duration: 250.ms,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : AppColors.outlineVariant.withValues(alpha: 0.3),
                    width: selected ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profile.name,
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  profile.lastVerifiedLabel,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: selected
                                ? AppColors.primary
                                : AppColors.outlineVariant,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Organizations: ${profile.activeOrganizationsLabel}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: profile.needs.take(3).map((need) {
                          final needName = _humanizeNeed(need.needType);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              needName,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Color _needColor(String needType) {
    switch (needType) {
      case 'severe_acute_malnutrition':
        return const Color(0xFFc2410c);
      case 'wash_deficits':
        return const Color(0xFF0369a1);
      case 'maternal_health_gaps':
        return const Color(0xFF9d174d);
      case 'infrastructure_failures':
        return const Color(0xFF7c2d12);
      case 'livelihood_threats':
        return const Color(0xFF166534);
      default:
        return AppColors.primary;
    }
  }

  String _humanizeNeed(String needType) => needType.replaceAll('_', ' ');
}

class _MatrixRow extends StatelessWidget {
  final CommunityProfile profile;
  final List<(String, String)> categories;

  const _MatrixRow({required this.profile, required this.categories});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                profile.name,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          ...categories.map((category) {
            final severity = _severityFor(category.$1);
            final opacity = profile.isStale ? 0.32 : 0.18 + (severity * 0.78);
            return Container(
              width: 88,
              height: 42,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: _colorFor(
                  category.$1,
                ).withValues(alpha: opacity.clamp(0.0, 1.0)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.surfaceContainerHigh),
              ),
              child: Center(
                child: Text(
                  '${(severity * 100).round()}%',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: severity > 0.55 ? Colors.white : AppColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  double _severityFor(String needType) {
    final item = profile.matrix.cast<Map<String, dynamic>?>().firstWhere(
      (entry) => (entry?['need_type'] ?? '').toString() == needType,
      orElse: () => null,
    );
    if (item == null) {
      return profile.baseline.isNotEmpty ? 0.25 : 0.0;
    }
    final raw = (item['severity'] as num?)?.toDouble() ?? 0.0;
    return raw.clamp(0.0, 1.0);
  }

  Color _colorFor(String needType) {
    switch (needType) {
      case 'severe_acute_malnutrition':
        return const Color(0xFFc2410c);
      case 'wash_deficits':
        return const Color(0xFF0369a1);
      case 'maternal_health_gaps':
        return const Color(0xFF9d174d);
      case 'infrastructure_failures':
        return const Color(0xFF7c2d12);
      default:
        return const Color(0xFF166534);
    }
  }
}

class _ForceGraphView extends StatefulWidget {
  final List<CommunityProfile> profiles;
  final String? selectedCommunityId;
  final ValueChanged<String> onSelectCommunity;

  const _ForceGraphView({
    required this.profiles,
    required this.selectedCommunityId,
    required this.onSelectCommunity,
  });

  @override
  State<_ForceGraphView> createState() => _ForceGraphViewState();
}

class _ForceGraphViewState extends State<_ForceGraphView> {
  List<_GraphNode> _nodes = [];
  List<_GraphEdge> _edges = [];

  @override
  void initState() {
    super.initState();
    _rebuildNodes();
  }

  @override
  void didUpdateWidget(covariant _ForceGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profiles != widget.profiles ||
        oldWidget.selectedCommunityId != widget.selectedCommunityId) {
      _rebuildNodes();
    }
  }

  void _rebuildNodes() {
    final nodes = <_GraphNode>[];
    final edges = <_GraphEdge>[];
    final profiles = widget.profiles;
    if (profiles.isEmpty) {
      setState(() => _nodes = []);
      return;
    }

    final widthIndex = profiles.length.clamp(1, 12);

    // Create community nodes anchored to their geographic positions
    final communityNodes = <String, _GraphNode>{};
    for (var index = 0; index < profiles.length; index++) {
      final profile = profiles[index];
      final normalizedX = ((profile.longitude + 180.0) / 360.0).clamp(
        0.10,
        0.90,
      );
      final normalizedY = ((90.0 - profile.latitude) / 180.0).clamp(0.10, 0.90);
      final base = Offset(normalizedX, normalizedY);
      final communityNode = _GraphNode(
        id: profile.id,
        label: profile.name,
        kind: _GraphNodeKind.community,
        color: AppColors.primary,
        position: base,
        radius: profile.id == widget.selectedCommunityId ? 0.048 : 0.038,
        metadata: profile,
        anchor: base, // Keep community nodes anchored to geographic positions
      );
      nodes.add(communityNode);
      communityNodes[profile.id] = communityNode;
    }

    // Create NGO nodes and edges with stronger connections
    for (var index = 0; index < profiles.length; index++) {
      final profile = profiles[index];
      final communityNode = communityNodes[profile.id]!;

      final ngos = [
        if (profile.ngo.isNotEmpty)
          profile.ngo['name']?.toString() ??
              profile.ngo['id']?.toString() ??
              'NGO',
        ...profile.targetNgos.take(2),
      ].where((value) => value.trim().isNotEmpty).toList();

      // Create NGO nodes positioned in a circle around the community
      for (var ngoIndex = 0; ngoIndex < ngos.length; ngoIndex++) {
        final angle = (ngoIndex / math.max(1, ngos.length)) * math.pi * 2.0;
        final offset = Offset(
          math.cos(angle) * 0.10,
          math.sin(angle) * 0.10,
        ); // Larger offset for better visibility
        final nodeId = '${profile.id}:ngo:$ngoIndex';
        final ngoNode = _GraphNode(
          id: nodeId,
          label: ngos[ngoIndex],
          kind: _GraphNodeKind.ngo,
          color: _ngoColor(ngoIndex),
          position: (communityNode.position + offset).clamp(
            const Offset(0.05, 0.05),
            const Offset(0.95, 0.95),
          ),
          radius: 0.024,
          metadata: profile,
          anchor:
              communityNode.position +
              offset, // Anchor NGO relative to community
        );
        nodes.add(ngoNode);

        // Create strong edges between communities and NGOs
        final edgeNeed = profile.needs.isNotEmpty
            ? profile.needs[ngoIndex % profile.needs.length]
            : null;
        edges.add(
          _GraphEdge(
            from: profile.id,
            to: nodeId,
            color: edgeNeed == null
                ? AppColors.outlineVariant
                : _needColor(edgeNeed.needType),
            opacity: profile.isStale ? 0.30 : 0.85,
            strength: 0.15, // Stronger spring force
          ),
        );
      }

      // Add edges between nearby communities (similarity-based)
      if (profile.similarity.isNotEmpty) {
        for (var sim in profile.similarity.take(2)) {
          final similarCommunityId = sim['community_id']?.toString() ?? '';
          if (communityNodes.containsKey(similarCommunityId)) {
            edges.add(
              _GraphEdge(
                from: profile.id,
                to: similarCommunityId,
                color: AppColors.primary.withValues(alpha: 0.4),
                opacity: 0.20,
                strength: 0.08,
              ),
            );
          }
        }
      }
    }

    _relax(nodes, edges, widthIndex);
    setState(() {
      _nodes = nodes;
      _edges = edges;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_nodes.isEmpty) {
      return const Center(child: Text('No network data available'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final graph = SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GraphEdgePainter(nodes: _nodes, edges: _edges),
                ),
              ),
              ..._nodes.map((node) {
                final x = node.position.dx * width;
                final y = node.position.dy * height;
                final selected =
                    node.kind == _GraphNodeKind.community &&
                    node.id == widget.selectedCommunityId;
                return Positioned(
                  left: x - (node.radius * width),
                  top: y - (node.radius * height),
                  child: GestureDetector(
                    onTap: () {
                      if (node.kind == _GraphNodeKind.community) {
                        widget.onSelectCommunity(node.id);
                        final raw = node.metadata;
                        if (raw is CommunityProfile) {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  CommunityDetailScreen(profile: raw),
                            ),
                          );
                        }
                      }
                    },
                    child: AnimatedContainer(
                      duration: 240.ms,
                      width: node.radius * width * 2,
                      height: node.radius * height * 2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: node.color.withValues(
                          alpha: selected
                              ? 1.0
                              : (node.kind == _GraphNodeKind.ngo ? 0.86 : 0.92),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: node.color.withValues(alpha: 0.18),
                            blurRadius: selected ? 24 : 16,
                            offset: const Offset(0, 10),
                          ),
                        ],
                        border: Border.all(
                          color: selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.16),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            node.kind == _GraphNodeKind.community
                                ? node.label
                                : _shortLabel(node.label),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );

        return InteractiveViewer(
          minScale: 0.65,
          maxScale: 3.2,
          boundaryMargin: const EdgeInsets.all(120),
          child: graph,
        );
      },
    );
  }

  void _relax(List<_GraphNode> nodes, List<_GraphEdge> edges, int iterations) {
    if (nodes.isEmpty) return;

    final rng = math.Random(13);
    for (final node in nodes) {
      node.velocity = Offset(
        (rng.nextDouble() - 0.5) * 0.008,
        (rng.nextDouble() - 0.5) * 0.008,
      );
    }

    for (var iteration = 0; iteration < iterations * 15; iteration++) {
      // Repulsive forces between all nodes
      for (var i = 0; i < nodes.length; i++) {
        for (var j = i + 1; j < nodes.length; j++) {
          final a = nodes[i];
          final b = nodes[j];
          final delta = b.position - a.position;
          final distance = math.max(0.01, delta.distance);
          final repulsion = 0.0020 / (distance * distance);
          final force = delta / distance * repulsion;
          a.velocity -= force;
          b.velocity += force;
        }
      }

      // Attractive forces along edges (springs)
      for (final edge in edges) {
        final source = nodes.firstWhere(
          (node) => node.id == edge.from,
          orElse: () => nodes.first,
        );
        final target = nodes.firstWhere(
          (node) => node.id == edge.to,
          orElse: () => nodes.first,
        );
        final delta = target.position - source.position;
        final distance = math.max(0.01, delta.distance);
        final spring = (distance - 0.10) * (edge.strength ?? 0.10);
        final force = delta / distance * spring;
        source.velocity += force;
        target.velocity -= force;
      }

      // Apply anchor constraints and damping
      for (final node in nodes) {
        final anchor = node.anchor ?? node.position;
        if (node.kind == _GraphNodeKind.community) {
          // Communities stay anchored to geographic positions
          final pull = (anchor - node.position) * 0.06;
          node.velocity += pull;
        } else {
          // NGOs pull towards their parent community but with some freedom
          final pull = (anchor - node.position) * 0.04;
          node.velocity += pull;
        }

        node.position = (node.position + node.velocity).clamp(
          const Offset(0.03, 0.03),
          const Offset(0.97, 0.97),
        );
        node.velocity *= 0.82; // Damping to stabilize layout
      }
    }
  }

  Color _needColor(String needType) {
    switch (needType) {
      case 'severe_acute_malnutrition':
        return const Color(0xFFc2410c);
      case 'wash_deficits':
        return const Color(0xFF0369a1);
      case 'maternal_health_gaps':
        return const Color(0xFF9d174d);
      case 'infrastructure_failures':
        return const Color(0xFF7c2d12);
      case 'livelihood_threats':
        return const Color(0xFF166534);
      default:
        return AppColors.primary;
    }
  }

  Color _ngoColor(int index) {
    const colors = [
      Color(0xFF0f766e),
      Color(0xFF7c3aed),
      Color(0xFFb45309),
      Color(0xFF1d4ed8),
    ];
    return colors[index % colors.length];
  }

  String _shortLabel(String value) {
    if (value.length <= 14) {
      return value;
    }
    return '${value.substring(0, 11).trimRight()}…';
  }
}

enum _GraphNodeKind { community, ngo }

class _GraphNode {
  final String id;
  final String label;
  final _GraphNodeKind kind;
  final Color color;
  final double radius;
  final dynamic metadata;
  Offset position;
  Offset velocity = Offset.zero;
  Offset? anchor;

  _GraphNode({
    required this.id,
    required this.label,
    required this.kind,
    required this.color,
    required this.position,
    required this.radius,
    this.metadata,
    this.anchor,
  });
}

class _GraphEdge {
  final String from;
  final String to;
  final Color color;
  final double opacity;
  final double? strength;

  _GraphEdge({
    required this.from,
    required this.to,
    required this.color,
    required this.opacity,
    this.strength = 0.10,
  });
}

class _GraphEdgePainter extends CustomPainter {
  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;

  _GraphEdgePainter({required this.nodes, required this.edges});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (final edge in edges) {
      final source = nodes.firstWhere(
        (node) => node.id == edge.from,
        orElse: () => nodes.first,
      );
      final target = nodes.firstWhere(
        (node) => node.id == edge.to,
        orElse: () => nodes.first,
      );
      paint.color = edge.color.withValues(alpha: edge.opacity);
      final p1 = Offset(
        source.position.dx * size.width,
        source.position.dy * size.height,
      );
      final p2 = Offset(
        target.position.dx * size.width,
        target.position.dy * size.height,
      );
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..quadraticBezierTo(
          (p1.dx + p2.dx) / 2,
          math.min(p1.dy, p2.dy) - 20,
          p2.dx,
          p2.dy,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphEdgePainter oldDelegate) =>
      oldDelegate.nodes != nodes;
}

extension _OffsetClamp on Offset {
  Offset clamp(Offset min, Offset max) => Offset(
    dx.clamp(min.dx, max.dx).toDouble(),
    dy.clamp(min.dy, max.dy).toDouble(),
  );
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
