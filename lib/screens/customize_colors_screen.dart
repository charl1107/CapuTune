import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/theme_service.dart';
import '../theme/design_style.dart';
import '../widgets/theme_live_preview_card.dart';
import '../widgets/visual_color_picker_sheet.dart';

class _ColorField {
  final String label;
  final String description;
  final Color Function(StyleColors) get;
  final StyleColors Function(StyleColors, Color) set;

  const _ColorField({
    required this.label,
    required this.description,
    required this.get,
    required this.set,
  });
}

/// The 7 core theme properties supported by CapuTune:
/// Background, Surface, Card, Accent, Highlight, Border, Ambient Glow.
final List<_ColorField> _kThemeColorProperties = [
  _ColorField(
    label: 'Background',
    description: 'Main screen backdrop fill',
    get: (t) => t.background,
    set: (t, c) => t.copyWith(background: c),
  ),
  _ColorField(
    label: 'Surface',
    description: 'App bars, dialogs and elevated containers',
    get: (t) => t.surface,
    set: (t, c) => t.copyWith(surface: c),
  ),
  _ColorField(
    label: 'Card',
    description: 'List items, song cards and content panels',
    get: (t) => t.card,
    set: (t, c) => t.copyWith(card: c),
  ),
  _ColorField(
    label: 'Accent',
    description: 'Primary action buttons, sliders and active indicators',
    get: (t) => t.accent,
    set: (t, c) => t.copyWith(accent: c),
  ),
  _ColorField(
    label: 'Highlight',
    description: 'Secondary accents, status dots and focus rings',
    get: (t) => t.highlight,
    set: (t, c) => t.copyWith(highlight: c),
  ),
  _ColorField(
    label: 'Border',
    description: 'Divider lines, card outlines and hairline boundaries',
    get: (t) => t.border,
    set: (t, c) => t.copyWith(border: c),
  ),
  _ColorField(
    label: 'Ambient Glow',
    description: 'Atmospheric light cast behind cards and headers',
    get: (t) => t.glow,
    set: (t, c) => t.copyWith(glow: c),
  ),
];

/// Dedicated Customize Colors page with live preview and visual color selection.
class CustomizeColorsScreen extends StatefulWidget {
  const CustomizeColorsScreen({super.key});

  @override
  State<CustomizeColorsScreen> createState() => _CustomizeColorsScreenState();
}

class _CustomizeColorsScreenState extends State<CustomizeColorsScreen> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _openColorPicker(_ColorField property) async {
    final themeService = context.read<ThemeService>();
    final currentTokens = themeService.colors;
    final initialColor = property.get(currentTokens);

    // Provide context for contrast calculation
    final isBgOrSurface = property.label == 'Background' || property.label == 'Surface' || property.label == 'Card';
    final textColorContext = isBgOrSurface ? currentTokens.textPrimary : null;
    final bgColorContext = !isBgOrSurface ? currentTokens.background : null;

    final pickedColor = await VisualColorPickerSheet.show(
      context: context,
      title: 'Pick ${property.label} Color',
      initialColor: initialColor,
      textColorContext: textColorContext,
      backgroundColorContext: bgColorContext,
    );

    // If cancelled or unchanged, do not overwrite
    if (pickedColor == null || pickedColor == initialColor) return;

    // Apply change immediately to active theme & live preview
    themeService.updateColor((t) => property.set(t, pickedColor));
  }

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final tokens = themeService.colors;
    final currentStyle = themeService.style;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customize Colors'),
        actions: [
          if (themeService.isCustomized || themeService.activeCustomId != null)
            TextButton(
              onPressed: () => themeService.resetToDefault(),
              child: const Text('Reset'),
            ),
        ],
      ),
      body: ListView(
        children: [
          // 1. Live Interactive Theme Preview Card
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'LIVE PREVIEW — ${currentStyle.label}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: tokens.accent,
              ),
            ),
          ),
          ThemeLivePreviewCard(
            tokens: tokens,
            style: currentStyle,
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Theme Properties',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),

          // 2. Compact List Rows for each property
          for (final prop in _kThemeColorProperties)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: GestureDetector(
                onTap: () => _openColorPicker(prop),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: prop.get(tokens),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: tokens.border,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: prop.get(tokens).withValues(alpha: 0.25),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              title: Text(
                prop.label,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
              subtitle: Text(
                '${colorToHex(prop.get(tokens))} • ${prop.description}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.textSecondary,
                ),
              ),
              trailing: const Icon(Icons.colorize_outlined, size: 20),
              onTap: () => _openColorPicker(prop),
            ),

          const Divider(height: 28),

          // 3. Save Theme Section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'Save as Custom Theme',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'Theme name (e.g. Midnight Violet)',
                      hintStyle: TextStyle(color: tokens.textSecondary),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.accent,
                    foregroundColor: tokens.isDark ? tokens.background : Colors.white,
                  ),
                  onPressed: () {
                    final name = _nameController.text.trim();
                    themeService.saveCustomTheme(name.isEmpty ? 'Custom Theme' : name);
                    _nameController.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Saved "${name.isEmpty ? 'Custom Theme' : name}"'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
