import 'dart:ui';

/// Maps a normalized value (0..1) onto a green->amber->red scale
/// (green = best/lowest, red = worst/highest), per REQ UI-6.
class MetricColor {
  static Color forValue(num value, num min, num max) {
    if (max <= min) return const Color(0xFF4CAF50);
    final t = ((value - min) / (max - min)).clamp(0.0, 1.0);
    // green (0) -> amber (0.5) -> red (1)
    const green = Color(0xFF2E7D32);
    const amber = Color(0xFFF9A825);
    const red = Color(0xFFC62828);
    if (t < 0.5) {
      return Color.lerp(green, amber, t / 0.5)!;
    }
    return Color.lerp(amber, red, (t - 0.5) / 0.5)!;
  }
}
