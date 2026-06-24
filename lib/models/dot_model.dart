class Dot {
  final double x;
  final double y;
  final int sequenceOrder;
  final String label;
  final bool isNewPath; // ✍️ Keep this!

  Dot({
    required this.x,
    required this.y,
    required this.sequenceOrder,
    required this.label,
    this.isNewPath = false,
  });

  // 🎯 FIXED: Added isNewPath to copyWith so it's not lost during edits
  Dot copyWith({
    double? x,
    double? y,
    int? sequenceOrder,
    String? label,
    bool? isNewPath,
  }) {
    return Dot(
      x: x ?? this.x,
      y: y ?? this.y,
      sequenceOrder: sequenceOrder ?? this.sequenceOrder,
      label: label ?? this.label,
      isNewPath: isNewPath ?? this.isNewPath,
    );
  }

  factory Dot.fromJson(Map<String, dynamic> json) {
    // 🛡️ Get the order first, safely
    final int order = (json['sequence_order'] ?? 1) as int;

    return Dot(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      sequenceOrder: order,
      // 🎯 If label is missing, use the order. If order is missing, use '1'
      label: json['label']?.toString() ?? order.toString(),
      isNewPath: json['is_new_path'] ?? false,
    );
  }

  // 🎯 Add this to ensure Supabase saves the 'jump' property
  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'sequence_order': sequenceOrder,
    'label': label,
    'is_new_path': isNewPath,
  };

  factory Dot.fromIndexedList(int index, dynamic list) {
    return Dot(
      x: (list[0] as num).toDouble(),
      y: (list[1] as num).toDouble(),
      sequenceOrder: index + 1,
      label: (index + 1).toString(),
      isNewPath: false, // Initial AI dots usually aren't jumps
    );
  }

  factory Dot.fromMap(Map<String, dynamic> map) {
    // 🛡️ Safe extraction of sequence order
    final int order = (map['sequence_order'] ?? 1) as int;

    return Dot(
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
      sequenceOrder: order,
      // 🎯 Use the label if it exists, otherwise fallback to the order string
      label: map['label']?.toString() ?? order.toString(),
      isNewPath: map['is_new_path'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'x': x,
    'y': y,
    'sequence_order': sequenceOrder,
    'label': label,
    'is_new_path': isNewPath,
  };
}
