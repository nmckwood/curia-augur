import 'dart:ui';

import '../theme/palette.dart';

/// Maps a deprivation-delta value onto the diverging blue -> grey -> red ramp
/// (REQ UI-6). The original green -> amber -> red scale was dropped for WCAG 2.2
/// SC 1.4.1: red/green is the most commonly confused pair under colour-vision
/// deficiency. Every place this colour is used also prints the value as text, so the
/// hue is a shortcut rather than the only way to read the number.
class MetricColor {
  static Color forValue(num value, num min, num max) =>
      Palette.forValue(value, min, max);
}
