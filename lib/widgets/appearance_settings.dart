import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/customize_colors_screen.dart';
import '../services/theme_service.dart';
import '../theme/design_style.dart';

/// Extension providing short descriptions and full labels for each preset.
extension DesignStyleDisplay on DesignStyle {
  String get displayLabel => switch (this) {
        DesignStyle.glassmorphism => 'Glassmorphism',
        DesignStyle.ambient => 'Ambient UI',
        DesignStyle.neobrutalism => 'Neo-brutalism',
        DesignStyle.premium => 'Premium UI',
        DesignStyle.cyberpunk => 'Cyberpunk / Neon',
      };

  String get description => switch (this) {
        DesignStyle.glassmorphism => 'Frosted glass surfaces with soft purple glow',
        DesignStyle.ambient => 'Warm dark backdrop with generous ambient lighting',
        DesignStyle.neobrutalism => 'High contrast, bold borders and minimal glow',
        DesignStyle.premium => 'Refined dark slate with elegant gold accents',
        DesignStyle.cyberpunk => 'Deep black with vivid electric cyan and neon magenta',
      };
}

/// Compact swatch icon representing a theme style's color palette.
class ThemeStyleSwatch extends StatelessWidget {
  const ThemeStyleSwatch({
    super.key,
    required this.style,
    this.size = 28.0,
  });

  final DesignStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = DesignStylePalettes.of(style);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: palette.border,
          width: palette.borderWidth.clamp(1.0, 2.0),
        ),
      ),
      child: Center(
        child: Container(
          width: size * 0.45,
          height: size * 0.45,
          decoration: BoxDecoration(
            color: palette.accent,
            shape: BoxShape.circle,
            boxShadow: palette.glowStrength > 0
                ? [
                    BoxShadow(
                      color: palette.glow.withValues(alpha: 0.6),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

/// Settings → Appearance: compact vertical list consistent with the rest of
/// Settings. Each preset is a standard ListTile with a compact swatch icon,
/// title, short description, and selected-state indicator (radio button).
///
/// Followed by a compact "Customize Colors" row navigating to its own page,
/// optional saved custom themes, and a reset action.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final tokens = themeService.colors;
    final activeStyle = themeService.style;
    final isCustomized = themeService.isCustomized;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final style in DesignStyle.values)
          _ThemeListRow(
            style: style,
            selected: activeStyle == style && !isCustomized && themeService.activeCustomId == null,
            onTap: () => themeService.selectPreset(style),
          ),
        ListTile(
          leading: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            child: Icon(
              Icons.palette_outlined,
              size: 20,
              color: tokens.accent,
            ),
          ),
          title: const Text('Customize Colors'),
          subtitle: Text(
            isCustomized
                ? 'Customized from ${activeStyle.displayLabel}'
                : 'Edit background, surfaces, accent and glow',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CustomizeColorsScreen()),
            );
          },
        ),
        if (themeService.customThemes.isNotEmpty) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Saved Themes',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          for (final theme in themeService.customThemes)
            ListTile(
              leading: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: theme.colors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colors.border, width: 1),
                ),
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: theme.colors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              title: Text(theme.name),
              subtitle: Text(
                'Based on ${theme.preset.displayLabel}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    themeService.activeCustomId == theme.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                    color: themeService.activeCustomId == theme.id
                        ? tokens.accent
                        : tokens.textSecondary,
                  ),
                  PopupMenuButton<String>(
                    iconSize: 20,
                    onSelected: (action) =>
                        _onThemeAction(context, themeService, theme, action),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'apply', child: Text('Apply')),
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              onTap: () => themeService.selectCustomTheme(theme.id),
            ),
        ],
        if (isCustomized || themeService.activeCustomId != null)
          ListTile(
            leading: const SizedBox(
              width: 28,
              height: 28,
              child: Icon(Icons.restart_alt, size: 20),
            ),
            title: const Text('Reset to Default'),
            subtitle: Text(
              "Restore original ${activeStyle.displayLabel} palette",
              style: const TextStyle(fontSize: 12),
            ),
            onTap: () => themeService.resetToDefault(),
          ),
      ],
    );
  }

  void _onThemeAction(
    BuildContext context,
    ThemeService themeService,
    CustomTheme theme,
    String action,
  ) {
    switch (action) {
      case 'apply':
        themeService.selectCustomTheme(theme.id);
      case 'rename':
        _renameDialog(context, themeService, theme);
      case 'duplicate':
        themeService.duplicateCustomTheme(theme.id);
      case 'delete':
        themeService.deleteCustomTheme(theme.id);
    }
  }

  Future<void> _renameDialog(
    BuildContext context,
    ThemeService themeService,
    CustomTheme theme,
  ) async {
    final controller = TextEditingController(text: theme.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Theme'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      themeService.renameCustomTheme(theme.id, name);
    }
  }
}

class _ThemeListRow extends StatelessWidget {
  const _ThemeListRow({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final DesignStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<ThemeService>().colors;

    return ListTile(
      leading: ThemeStyleSwatch(style: style, size: 28),
      title: Text(
        style.displayLabel,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? tokens.accent : null,
        ),
      ),
      subtitle: Text(
        style.description,
        style: TextStyle(
          fontSize: 12,
          color: tokens.textSecondary,
        ),
      ),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 20,
        color: selected ? tokens.accent : tokens.textSecondary,
      ),
      onTap: onTap,
    );
  }
}
