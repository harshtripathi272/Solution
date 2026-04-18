import 'package:uuid/uuid.dart';

class CommunityNeedItem {
  final String needType;
  final double severity;
  final double confidence;
  final List<String> evidenceQuotes;
  final double acuteScore;
  final double chronicScore;

  CommunityNeedItem({
    required this.needType,
    required this.severity,
    required this.confidence,
    required this.evidenceQuotes,
    required this.acuteScore,
    required this.chronicScore,
  });

  factory CommunityNeedItem.fromMap(Map<String, dynamic> map) => CommunityNeedItem(
        needType: (map['need_type'] ?? map['needType'] ?? 'other').toString(),
        severity: (map['severity'] as num?)?.toDouble() ?? (map['chronic_score'] as num?)?.toDouble() ?? 0.0,
        confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
        evidenceQuotes: List<String>.from((map['evidence_quotes'] as List<dynamic>?) ?? const []),
        acuteScore: (map['acute_score'] as num?)?.toDouble() ?? 0.0,
        chronicScore: (map['chronic_score'] as num?)?.toDouble() ?? 0.0,
      );
}

class CommunityProfile {
  final String id;
  final String name;
  final String region;
  final String district;
  final String block;
  final double latitude;
  final double longitude;
  final List<String> keywords;
  final List<String> targetNgos;
  final Map<String, dynamic> baseline;
  final double freshnessWeight;
  final String adminLevel;
  final double resolutionConfidence;
  final Map<String, dynamic> report;
  final Map<String, dynamic> ngo;
  final List<CommunityNeedItem> needs;
  final List<Map<String, dynamic>> resources;
  final List<Map<String, dynamic>> similarity;
  final List<Map<String, dynamic>> coverageGaps;
  final List<Map<String, dynamic>> coordinationOpportunities;
  final List<Map<String, dynamic>> matrix;
  final Map<String, dynamic> provenance;
  final DateTime? updatedAt;
  final DateTime? lastVerifiedAt;

  CommunityProfile({
    required this.id,
    required this.name,
    required this.region,
    required this.district,
    required this.block,
    required this.latitude,
    required this.longitude,
    required this.keywords,
    required this.targetNgos,
    required this.baseline,
    required this.freshnessWeight,
    required this.adminLevel,
    required this.resolutionConfidence,
    required this.report,
    required this.ngo,
    required this.needs,
    required this.resources,
    required this.similarity,
    required this.coverageGaps,
    required this.coordinationOpportunities,
    required this.matrix,
    required this.provenance,
    required this.updatedAt,
    required this.lastVerifiedAt,
  });

  factory CommunityProfile.fromMap(Map<String, dynamic> map) {
    final community = Map<String, dynamic>.from(map['community'] as Map? ?? const {});
    final report = Map<String, dynamic>.from(map['report'] as Map? ?? const {});
    return CommunityProfile(
      id: (community['id'] ?? map['id'] ?? const Uuid().v4()).toString(),
      name: (community['name'] ?? 'Unknown').toString(),
      region: (community['region'] ?? '').toString(),
      district: (community['district'] ?? '').toString(),
      block: (community['block'] ?? '').toString(),
      latitude: (community['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (community['longitude'] as num?)?.toDouble() ?? 0.0,
      keywords: List<String>.from((community['keywords'] as List<dynamic>?) ?? const []),
      targetNgos: List<String>.from((community['target_ngos'] as List<dynamic>?) ?? const []),
      baseline: Map<String, dynamic>.from(community['baseline'] as Map? ?? const {}),
      freshnessWeight: (community['freshness_weight'] as num?)?.toDouble() ?? 0.0,
      adminLevel: (community['admin_level'] ?? 'village').toString(),
      resolutionConfidence: (community['resolution_confidence'] as num?)?.toDouble() ?? 0.0,
      report: report,
      ngo: Map<String, dynamic>.from(map['ngo'] as Map? ?? const {}),
      needs: ((map['needs'] as List<dynamic>?) ?? const []).map((entry) => CommunityNeedItem.fromMap(Map<String, dynamic>.from(entry as Map))).toList(),
      resources: List<Map<String, dynamic>>.from((map['resources'] as List<dynamic>?)?.map((entry) => Map<String, dynamic>.from(entry as Map)) ?? const []),
      similarity: List<Map<String, dynamic>>.from((map['similarity'] as List<dynamic>?)?.map((entry) => Map<String, dynamic>.from(entry as Map)) ?? const []),
      coverageGaps: List<Map<String, dynamic>>.from((map['coverage_gaps'] as List<dynamic>?)?.map((entry) => Map<String, dynamic>.from(entry as Map)) ?? const []),
      coordinationOpportunities: List<Map<String, dynamic>>.from((map['coordination_opportunities'] as List<dynamic>?)?.map((entry) => Map<String, dynamic>.from(entry as Map)) ?? const []),
      matrix: List<Map<String, dynamic>>.from((map['matrix'] as List<dynamic>?)?.map((entry) => Map<String, dynamic>.from(entry as Map)) ?? const []),
      provenance: Map<String, dynamic>.from(map['provenance'] as Map? ?? const {}),
      updatedAt: DateTime.tryParse((map['updated_at'] ?? '').toString()),
      lastVerifiedAt: DateTime.tryParse((map['last_verified_at'] ?? '').toString()),
    );
  }

  String get activeOrganizationsLabel {
    final fromNgo = ngo.isEmpty ? <String>[] : [(ngo['name'] ?? ngo['id'] ?? '').toString()];
    final organizations = [...fromNgo, ...targetNgos].where((value) => value.trim().isNotEmpty).toSet().toList();
    if (organizations.isEmpty) {
      return 'No active organizations';
    }
    return organizations.take(3).join(', ');
  }

  String get lastVerifiedLabel {
    final value = lastVerifiedAt ?? updatedAt;
    if (value == null) {
      return 'Pending verification';
    }
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  bool get isStale {
    final value = lastVerifiedAt ?? updatedAt;
    if (value == null) {
      return true;
    }
    return DateTime.now().difference(value).inDays > 180;
  }
}

class CommunityGraphOverview {
  final DateTime generatedAt;
  final List<CommunityProfile> profiles;
  final List<Map<String, dynamic>> matrix;
  final List<Map<String, dynamic>> coverageGaps;
  final List<Map<String, dynamic>> coordinationOpportunities;

  CommunityGraphOverview({
    required this.generatedAt,
    required this.profiles,
    required this.matrix,
    required this.coverageGaps,
    required this.coordinationOpportunities,
  });

  factory CommunityGraphOverview.fromMap(Map<String, dynamic> map) => CommunityGraphOverview(
        generatedAt: DateTime.tryParse((map['generated_at'] ?? '').toString()) ?? DateTime.now(),
        profiles: ((map['profiles'] as List<dynamic>?) ?? const [])
            .map((entry) => CommunityProfile.fromMap(Map<String, dynamic>.from(entry as Map)))
            .toList(),
        matrix: List<Map<String, dynamic>>.from((map['matrix'] as List<dynamic>?)?.map((entry) => Map<String, dynamic>.from(entry as Map)) ?? const []),
        coverageGaps: List<Map<String, dynamic>>.from((map['coverage_gaps'] as List<dynamic>?)?.map((entry) => Map<String, dynamic>.from(entry as Map)) ?? const []),
        coordinationOpportunities: List<Map<String, dynamic>>.from((map['coordination_opportunities'] as List<dynamic>?)?.map((entry) => Map<String, dynamic>.from(entry as Map)) ?? const []),
      );

  bool get hasProfiles => profiles.isNotEmpty;
}
