class DiaRepouso {
  const DiaRepouso({
    required this.data,
    required this.mediaFcRepouso,
    required this.mediaVfcRepouso,
  });

  final DateTime data;
  final double mediaFcRepouso;
  final double mediaVfcRepouso;

  Map<String, dynamic> toJson() => {
        'data': data.toIso8601String(),
        'mediaFcRepouso': mediaFcRepouso,
        'mediaVfcRepouso': mediaVfcRepouso,
      };

  factory DiaRepouso.fromJson(Map<String, dynamic> json) {
    return DiaRepouso(
      data: DateTime.parse(json['data'] as String),
      mediaFcRepouso: (json['mediaFcRepouso'] as num).toDouble(),
      mediaVfcRepouso: (json['mediaVfcRepouso'] as num).toDouble(),
    );
  }
}
