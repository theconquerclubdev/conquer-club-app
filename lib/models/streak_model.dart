// lib/models/streak_model.dart
class StreakModel {
  final String id;
  final String memberId;
  final DateTime date;
  final bool isWorkoutCompleted;
  final bool isStepsCompleted;
  final bool isPhotosUploaded;
  final bool isMeasurementsUpdated;
  final int workoutMinutes;
  final int stepsCount;
  final bool isSunday;
  final bool isStreakMet;
  final DateTime createdAt;
  final DateTime updatedAt;

  StreakModel({
    required this.id,
    required this.memberId,
    required this.date,
    required this.isWorkoutCompleted,
    required this.isStepsCompleted,
    required this.isPhotosUploaded,
    required this.isMeasurementsUpdated,
    required this.workoutMinutes,
    required this.stepsCount,
    required this.isSunday,
    required this.isStreakMet,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StreakModel.fromJson(Map<String, dynamic> json) {
    return StreakModel(
      id: json['id'] ?? '',
      memberId: json['member_id'] ?? '',
      date: DateTime.parse(json['date'] ?? DateTime.now().toIso8601String()),
      isWorkoutCompleted: json['is_workout_completed'] ?? false,
      isStepsCompleted: json['is_steps_completed'] ?? false,
      isPhotosUploaded: json['is_photos_uploaded'] ?? false,
      isMeasurementsUpdated: json['is_measurements_updated'] ?? false,
      workoutMinutes: json['workout_minutes'] ?? 0,
      stepsCount: json['steps_count'] ?? 0,
      isSunday: json['is_sunday'] ?? false,
      isStreakMet: json['is_streak_met'] ?? false,
      createdAt: DateTime.parse(
          json['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(
          json['updated_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'member_id': memberId,
      'date': date.toIso8601String().split('T').first,
      'is_workout_completed': isWorkoutCompleted,
      'is_steps_completed': isStepsCompleted,
      'is_photos_uploaded': isPhotosUploaded,
      'is_measurements_updated': isMeasurementsUpdated,
      'workout_minutes': workoutMinutes,
      'steps_count': stepsCount,
      'is_sunday': isSunday,
      'is_streak_met': isStreakMet,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
