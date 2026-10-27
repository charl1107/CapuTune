import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Ready-made quick palette swatches organized by color family.
/// Hand-tuned to look excellent with both dark music-app themes and light accents.
class QuickSwatches {
  QuickSwatches._();

  static const List<Color> curated = [
    // Purples & Violets
    Color(0xFF7C4DFF),
    Color(0xFF9575CD),
    Color(0xFFB388FF),
    Color(0xFF651FFF),
    // Blues & Cyans
    Color(0xFF00E5FF),
    Color(0xFF2979FF),
    Color(0xFF00B0FF),
    Color(0xFF03A9F4),
    // Greens & Teals
    Color(0xFF00E676),
    Color(0xFF1DE9B6),
    Color(0xFF69F0AE),
    Color(0xFF00BFA5),
    // Pinks & Reds
    Color(0xFFFF2E88),
    Color(0xFFFF5252),
    Color(0xFFFF4081),
    Color(0xFFF06292),
    // Oranges & Yellows / Golds
    Color(0xFFFF9100),
    Color(0xFFFFD700),
    Color(0xFFC9A96A),
    Color(0xFFFFAB40),
    // Monochromes & Neutrals
    Color(0xFFFFFFFF),
    Color(0xFFB0BEC5),
    Color(0xFF455A64),
    Color(0xFF1E1E24),
    Color(0xFF121218),
    Color(0xFF050508),
  ];
}

/// Helper to format Color into a 6-digit hex string (#RRGGBB).
String colorToHex(Color color, {bool includeHash = true}) {
  final rgb = color.toARGB32() & 0x00FFFFFF;
  final hex = rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
  return includeHash ? '#$hex' : hex;
}

/// Calculates relative luminance according to WCAG standards.
double computeLuminance(Color color) {
  double channel(int c) {
    final v = c / 255.0;
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  final argb = color.toARGB32();
  final r = channel((argb >> 16) & 0xFF);
  final g = channel((argb >> 8) & 0xFF);
  final b = channel(argb & 0xFF);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Contrast ratio between two colors: (L1 + 0.05) / (L2 + 0.05).
double computeContrastRatio(Color foreground, Color background) {
  final l1 = computeLuminance(foreground);
  final l2 = computeLuminance(background);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// A beginner-friendly, visual color picker modal sheet.
/// Includes:
/// 1. Hue bar + 2D Saturation/Value spectrum area (drag or tap).
/// 2. Clear color preview (before vs new).
/// 3. Readability / contrast warning if text/background become illegible.
/// 4. Quick swatches row/grid.
/// 5. Optional expandable "Enter hex code" for advanced users with input validation.
/// 6. Apply and Cancel actions.
class VisualColorPickerSheet extends StatefulWidget {
  const VisualColorPickerSheet({
    super.key,
    required this.title,
    required this.initialColor,
    this.backgroundColorContext,
    this.textColorContext,
  });

  final String title;
  final Color initialColor;

  /// Optional context colors to check readability/contrast against.
  final Color? backgroundColorContext;
  final Color? textColorContext;

  /// Opens the modal sheet and returns the selected [Color] or null on cancel.
  static Future<Color?> show({
    required BuildContext context,
    required String title,
    required Color initialColor,
    Color? backgroundColorContext,
    Color? textColorContext,
  }) {
    return showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VisualColorPickerSheet(
        title: title,
        initialColor: initialColor,
        backgroundColorContext: backgroundColorContext,
        textColorContext: textColorContext,
      ),
    );
  }

  @override
  State<VisualColorPickerSheet> createState() => _VisualColorPickerSheetState();
}

class _VisualColorPickerSheetState extends State<VisualColorPickerSheet> {
  late HSVColor _hsv;
  late TextEditingController _hexController;
  String? _hexError;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor.withValues(alpha: 1.0));
    _hexController = TextEditingController(text: colorToHex(_hsv.toColor()));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _currentColor => _hsv.toColor();

  void _onColorChanged(HSVColor newHsv) {
    setState(() {
      _hsv = newHsv;
      _hexController.text = colorToHex(_hsv.toColor());
      _hexError = null;
    });
  }

  void _onHexSubmitted(String input) {
    var raw = input.trim();
    if (raw.startsWith('#')) raw = raw.substring(1);

    if (raw.length != 6) {
      setState(() => _hexError = 'Please enter a 6-digit hex code (e.g. #7C4DFF)');
      return;
    }

    final intVal = int.tryParse('FF$raw', radix: 16);
    if (intVal == null) {
      setState(() => _hexError = 'Invalid hex format. Use digits 0-9 and A-F.');
      return;
    }

    final color = Color(intVal);
    setState(() {
      _hsv = HSVColor.fromColor(color);
      _hexError = null;
    });
  }

  String? _computeContrastWarning() {
    // If customising background, compare against text color
    if (widget.textColorContext != null) {
      final ratio = computeContrastRatio(widget.textColorContext!, _currentColor);
      if (ratio < 3.0) {
        return 'Warning: Low contrast with text (${ratio.toStringAsFixed(1)}:1). Text may be difficult to read.';
      }
    }
    // If customising text or accent, compare against background
    if (widget.backgroundColorContext != null) {
      final ratio = computeContrastRatio(_currentColor, widget.backgroundColorContext!);
      if (ratio < 3.0) {
        return 'Warning: Low contrast with background (${ratio.toStringAsFixed(1)}:1). Elements may blend in.';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contrastWarning = _computeContrastWarning();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1), width: 1),
      ),
      padding: EdgeInsets.only(
        top: 14,
        left: 18,
        right: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header row with Title and actions
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _currentColor),
                  child: const Text('Apply'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Color preview (Initial vs Selected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  // Swatches
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.initialColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.dividerColor,
                        width: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _currentColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.onSurfaceVariant,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _currentColor.withValues(alpha: 0.35),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          colorToHex(_currentColor),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Tap or drag spectrum below',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Contrast Warning Alert if any
            if (contrastWarning != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        contrastWarning,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.amberAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 1. Saturation / Value 2D Area
            SizedBox(
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _SaturationValueArea(
                  hsv: _hsv,
                  onChanged: _onColorChanged,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 2. Hue Slider
            _HueSlider(
              hue: _hsv.hue,
              onChanged: (h) => _onColorChanged(_hsv.withHue(h)),
            ),
            const SizedBox(height: 14),

            // 3. Quick Color Swatches
            const Text(
              'Quick Colors',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final swatch in QuickSwatches.curated)
                  _SwatchCircle(
                    color: swatch,
                    isSelected: (swatch.toARGB32() & 0x00FFFFFF) ==
                        (_currentColor.toARGB32() & 0x00FFFFFF),
                    onTap: () {
                      _onColorChanged(HSVColor.fromColor(swatch));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // 4. Optional Hex Code Input (Advanced)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                setState(() => _showAdvanced = !_showAdvanced);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showAdvanced
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Enter Hex Code (Advanced)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showAdvanced) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hexController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Hex (#RRGGBB)',
                        hintText: '#7C4DFF',
                        isDense: true,
                        errorText: _hexError,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: _onHexSubmitted,
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonal(
                    onPressed: () => _onHexSubmitted(_hexController.text),
                    child: const Text('Update'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Circular Quick Swatch with highlight border when selected.
class _SwatchCircle extends StatelessWidget {
  const _SwatchCircle({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.onSurface
                : theme.dividerColor.withValues(alpha: 0.5),
            width: isSelected ? 2.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        child: isSelected
            ? Center(
                child: Icon(
                  Icons.check,
                  size: 16,
                  color: computeContrastRatio(Colors.white, color) >= 3
                      ? Colors.white
                      : Colors.black,
                ),
              )
            : null,
      ),
    );
  }
}

/// 2D Saturation / Value Gradient box supporting tap & drag.
class _SaturationValueArea extends StatelessWidget {
  const _SaturationValueArea({
    required this.hsv,
    required this.onChanged,
  });

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _handleGesture(Offset localPos, Size size) {
    final s = (localPos.dx / size.width).clamp(0.0, 1.0);
    final v = (1.0 - (localPos.dy / size.height)).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return GestureDetector(
          onPanDown: (details) => _handleGesture(details.localPosition, size),
          onPanUpdate: (details) => _handleGesture(details.localPosition, size),
          child: CustomPaint(
            size: size,
            painter: _SaturationValuePainter(hsv: hsv),
          ),
        );
      },
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter({required this.hsv});

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final pureHue = HSVColor.fromAHSV(1.0, hsv.hue, 1.0, 1.0).toColor();

    // 1. Horizontal gradient: White -> Pure Hue
    final horizontalShader = LinearGradient(
      colors: [Colors.white, pureHue],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = horizontalShader);

    // 2. Vertical gradient: Transparent -> Black (Value)
    final verticalShader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = verticalShader);

    // 3. Thumb indicator for current (Saturation, Value)
    final thumbX = hsv.saturation * size.width;
    final thumbY = (1.0 - hsv.value) * size.height;
    final thumbCenter = Offset(thumbX, thumbY);

    // Outer dark stroke
    canvas.drawCircle(
      thumbCenter,
      9,
      Paint()
        ..color = Colors.black45
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    // Inner white stroke
    canvas.drawCircle(
      thumbCenter,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // Fill circle with current color
    canvas.drawCircle(
      thumbCenter,
      6.5,
      Paint()..color = hsv.toColor(),
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter old) => old.hsv != hsv;
}

/// Rainbow Hue slider with draggable track.
class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  static const List<Color> _hueColors = [
    Color(0xFFFF0000), // 0
    Color(0xFFFFFF00), // 60
    Color(0xFF00FF00), // 120
    Color(0xFF00FFFF), // 180
    Color(0xFF0000FF), // 240
    Color(0xFFFF00FF), // 300
    Color(0xFFFF0000), // 360
  ];

  void _handleGesture(Offset localPos, double width) {
    final h = (localPos.dx / width).clamp(0.0, 1.0) * 360.0;
    onChanged(h.clamp(0.0, 360.0));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const height = 24.0;

        return GestureDetector(
          onPanDown: (d) => _handleGesture(d.localPosition, width),
          onPanUpdate: (d) => _handleGesture(d.localPosition, width),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height / 2),
              gradient: const LinearGradient(colors: _hueColors),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: ((hue / 360.0) * width - (height / 2)).clamp(0.0, width - height),
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: height,
                    height: height,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor(),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.onSurface,
                        width: 2.5,
                      ),
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
