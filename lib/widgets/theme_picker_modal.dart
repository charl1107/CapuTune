import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/theme_service.dart';
import '../theme/design_style.dart';
import 'style_preview.dart';

/// Compact first-launch theme picker: a small centered dialog over the live
/// Home screen. Selecting a preset applies it immediately through
/// [ThemeService] (provider), so Home behind the dialog re-themes live.
///
/// Continue saves `pickerDone` and keeps the choice; Skip keeps the default
/// preset and still marks completion. Either way the modal never shows again.
Future<void> showThemePickerModal(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (dialogContext) => const ThemePickerModal(),
  );
}

class ThemePickerModal extends StatelessWidget {
  const ThemePickerModal({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final tokens = themeService.colors;
    final selected = themeService.style;

    return Dialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius),
        side: BorderSide(color: tokens.border, width: tokens.borderWidth),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose Your Look',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'You can change this anytime in Settings → Appearance.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final style in DesignStyle.values)
                        _PresetRow(
                          style: style,
                          selected: style == selected,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      // Skip: keep whatever the user previewed? No — spec:
                      // skip uses the default theme. Restore the default
                      // preset, then mark done.
                      themeService.selectPreset(DesignStyle.glassmorphism);
                      themeService.completeFirstLaunchPicker();
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Skip',
                      style: TextStyle(color: tokens.textSecondary),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor:
                          tokens.isDark ? tokens.background : Colors.white,
                    ),
                    onPressed: () {
                      themeService.completeFirstLaunchPicker();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.style, required this.selected});

  final DesignStyle style;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final tokens = themeService.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? tokens.accent.withValues(alpha: 0.14) : tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius * 0.75),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radius * 0.75),
          onTap: () => themeService.selectPreset(style),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radius * 0.75),
              border: Border.all(
                color: selected ? tokens.accent : tokens.border,
                width: selected ? 1.6 : tokens.borderWidth,
              ),
            ),
            child: Row(
              children: [
                StylePreview(style: style, size: const Size(64, 40)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    style.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 20,
                  color: selected ? tokens.accent : tokens.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
