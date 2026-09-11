class Project {
  final String id;
  final String name;
  final String? imagePath;
  final int dotCount;
  final String difficulty;
  final int lastIndex;
  final DateTime createdAt;
  final List<dynamic> dots;
  final List<dynamic> erasedPoints;
  final int sparsity;

  final bool isPublic;

  // Stars
  final bool easyCleared;
  final bool mediumCleared;
  final bool hardCleared;

  // Difficulty-calibrated dot sets (null until worker regenerates them)
  final List<dynamic>? dotsEasy;
  final List<dynamic>? dotsMedium;
  final List<dynamic>? dotsHard;

  Project({
    required this.id,
    required this.name,
    this.imagePath,
    this.dotCount = 0,
    this.difficulty = 'Easy',
    this.lastIndex = 0,
    required this.createdAt,
    this.dots = const [],
    this.erasedPoints = const [],
    this.sparsity = 20,
    this.isPublic = false,
    this.easyCleared = false,
    this.mediumCleared = false,
    this.hardCleared = false,
    this.dotsEasy,
    this.dotsMedium,
    this.dotsHard,
  });

  int get starCount {
    int count = 0;
    if (easyCleared) count++;
    if (mediumCleared) count++;
    if (hardCleared) count++;
    return count;
  }

  /// Returns the dot set for [level] ("easy"/"medium"/"hard"),
  /// falling back to [dots] if the calibrated set is absent.
  List<dynamic> dotsForLevel(String level) {
    switch (level) {
      case 'easy':
        if (dotsEasy != null && dotsEasy!.isNotEmpty) return dotsEasy!;
      case 'medium':
        if (dotsMedium != null && dotsMedium!.isNotEmpty) return dotsMedium!;
      case 'hard':
        if (dotsHard != null && dotsHard!.isNotEmpty) return dotsHard!;
    }
    return dots;
  }

  Project copyWith({
    String? id,
    String? name,
    String? imagePath,
    int? dotCount,
    String? difficulty,
    int? lastIndex,
    DateTime? createdAt,
    List<dynamic>? dots,
    List<dynamic>? erasedPoints,
    int? sparsity,
    bool? easyCleared,
    bool? mediumCleared,
    bool? hardCleared,
    List<dynamic>? dotsEasy,
    List<dynamic>? dotsMedium,
    List<dynamic>? dotsHard,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      imagePath: imagePath ?? this.imagePath,
      dotCount: dotCount ?? this.dotCount,
      difficulty: difficulty ?? this.difficulty,
      lastIndex: lastIndex ?? this.lastIndex,
      createdAt: createdAt ?? this.createdAt,
      dots: dots ?? this.dots,
      erasedPoints: erasedPoints ?? this.erasedPoints,
      sparsity: sparsity ?? this.sparsity,
      easyCleared: easyCleared ?? this.easyCleared,
      mediumCleared: mediumCleared ?? this.mediumCleared,
      hardCleared: hardCleared ?? this.hardCleared,
      dotsEasy: dotsEasy ?? this.dotsEasy,
      dotsMedium: dotsMedium ?? this.dotsMedium,
      dotsHard: dotsHard ?? this.dotsHard,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'image_path': imagePath,
      'dot_count': dotCount,
      'difficulty': difficulty,
      'last_index': lastIndex,
      'created_at': createdAt.toIso8601String(),
      'dots': dots,
      'erased_points': erasedPoints,
      'sparsity': sparsity,
      'easy_cleared': easyCleared,
      'medium_cleared': mediumCleared,
      'hard_cleared': hardCleared,
      'status': 'ready',
      if (dotsEasy != null) 'dots_easy': dotsEasy,
      if (dotsMedium != null) 'dots_medium': dotsMedium,
      if (dotsHard != null) 'dots_hard': dotsHard,
    };
  }

  factory Project.fromMap(Map<String, dynamic> map) {
    return Project(
      id: map['id'] ?? '',
      name: map['name'] ?? 'Untitled Puzzle',
      imagePath: map['image_path'],
      dotCount: map['dot_count'] ?? 0,
      difficulty: map['difficulty'] ?? 'Easy',
      lastIndex: map['last_index'] ?? 0,
      dots: map['dots'] ?? [],
      erasedPoints: map['erased_points'] ?? [],
      sparsity: map['sparsity'] ?? 20,
      isPublic: map['is_public'] ?? false,
      easyCleared: map['easy_cleared'] ?? false,
      mediumCleared: map['medium_cleared'] ?? false,
      hardCleared: map['hard_cleared'] ?? false,
      createdAt: DateTime.parse(
        map['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      dotsEasy: map['dots_easy'] as List<dynamic>?,
      dotsMedium: map['dots_medium'] as List<dynamic>?,
      dotsHard: map['dots_hard'] as List<dynamic>?,
    );
  }
}
