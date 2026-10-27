import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/storage_service.dart';
import '../theme/design_style.dart';

/// Owns the active visual identity and all persisted theme preferences.
///
/// Persistence rides the existing Hive `settings` box (StorageService), so
/// there is no new storage mechanism. Stored keys:
///
/// - `theme.style`         : DesignStyle name of the base preset
/// - `theme.colors`        : JSON recolor of that preset (null = default)
/// - `theme.customThemes`  : JSON list of saved named custom themes
/// - `theme.activeCustomId`: id of the active saved custom theme (null = none)
/// - `theme.pickerDone`    : first-launch picker completion flag
class ThemeService extends ChangeNotifier {
  ThemeService() {
    _style = _loadStyle();
    _colors = _loadColors();
    _customThemes = _loadCustomThemes();
    _activeCustomId = StorageService.getSetting<String?>(null, key: 'theme.activeCustomId');
    _pickerDone = StorageService.getSetting<bool>(false, key: 'theme.pickerDone');
  }

  late DesignStyle _style;

  /// Active tokens: either the preset palette or the user recolor of it.
  late StyleColors _colors;

  List<CustomTheme> _customThemes = [];
  String? _activeCustomId;
  bool _pickerDone = false;

  DesignStyle get style => _style;
  StyleColors get colors => _colors;
  List<CustomTheme> get customThemes => List.unmodifiable(_customThemes);
  String? get activeCustomId => _activeCustomId;
  bool get pickerDone => _pickerDone;

  /// True when the active colors differ from the base preset palette.
  bool get isCustomized {
    final base = DesignStylePalettes.of(_style);
    return _colors.background != base.background ||
        _colors.surface != base.surface ||
        _colors.card != base.card ||
        _colors.accent != base.accent ||
        _colors.highlight != base.highlight ||
        _colors.border != base.border ||
        _colors.glow != base.glow ||
        _colors.glowStrength != base.glowStrength ||
        _colors.textPrimary != base.textPrimary ||
        _colors.textSecondary != base.textSecondary ||
        _colors.isDark != base.isDark ||
        _colors.radius != base.radius ||
        _colors.borderWidth != base.borderWidth;
  }

  /// Selects a shipped preset: clears any recolor and custom-theme link.
  void selectPreset(DesignStyle style) {
    _style = style;
    _colors = DesignStylePalettes.of(style);
    _activeCustomId = null;
    _persistAll();
    notifyListeners();
  }

  /// Applies a saved custom theme by id. Unknown ids are ignored.
  void selectCustomTheme(String id) {
    for (final t in _customThemes) {
      if (t.id == id) {
        _style = t.preset;
        _colors = t.colors;
        _activeCustomId = id;
        _persistAll();
        notifyListeners();
        return;
      }
    }
  }

  /// Live-updates one token of the active palette (used by color pickers).
  ///
  /// Preserves the visual characteristics of the active preset ([useBlur],
  /// [useHardShadow], [useNeonGlow], [radius], [borderWidth]) so recoloring
  /// does not destroy the preset's identity.
  void updateColor(StyleColors Function(StyleColors) transform) {
    final base = DesignStylePalettes.of(_style);
    final updated = transform(_colors);
    _colors = updated.copyWith(
      useBlur: base.useBlur,
      useHardShadow: base.useHardShadow,
      useNeonGlow: base.useNeonGlow,
      radius: base.radius,
      borderWidth: base.borderWidth,
    );
    _activeCustomId = null;
    _persistColors();
    notifyListeners();
  }

  /// Restores the base palette of the current preset.
  void resetToDefault() {
    _colors = DesignStylePalettes.of(_style);
    _activeCustomId = null;
    _persistAll();
    notifyListeners();
  }

  bool customThemeNameExists(String name) =>
      _customThemes.any((t) => t.name.trim().toLowerCase() == name.trim().toLowerCase());

  /// Saves the current [colors] under [name] on top of [_style].
  ///
  /// Re-saving an existing name (case-insensitive) overwrites that theme.
  CustomTheme saveCustomTheme(String name) {
    final trimmed = name.trim();
    final existing = _customThemes
        .where((t) => t.name.trim().toLowerCase() == trimmed.toLowerCase())
        .firstOrNull;
    final theme = CustomTheme(
      id: existing?.id ?? 'ct_${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed.isEmpty ? 'My Theme' : trimmed,
      preset: _style,
      colors: _colors,
    );
    if (existing != null) {
      _customThemes[customThemes.indexWhere((t) => t.id == existing.id)] = theme;
    } else {
      _customThemes.add(theme);
    }
    _style = theme.preset;
    _colors = theme.colors;
    _activeCustomId = theme.id;
    _persistAll();
    notifyListeners();
    return theme;
  }

  /// Renames in place; keeps colors, preset, and active selection.
  void renameCustomTheme(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final i = _customThemes.indexWhere((t) => t.id == id);
    if (i == -1) return;
    _customThemes[i] = CustomTheme(
      id: id,
      name: trimmed,
      preset: _customThemes[i].preset,
      colors: _customThemes[i].colors,
    );
    _persistCustomThemes();
    notifyListeners();
  }

  /// Duplicates a saved theme as "<name> copy". Returns the new id, or null
  /// when [id] is unknown.
  String? duplicateCustomTheme(String id) {
    final i = _customThemes.indexWhere((t) => t.id == id);
    if (i == -1) return null;
    final src = _customThemes[i];
    var copyName = '${src.name} copy';
    var n = 2;
    while (customThemeNameExists(copyName)) {
      copyName = '${src.name} copy $n';
      n++;
    }
    final copy = CustomTheme(
      id: 'ct_${DateTime.now().microsecondsSinceEpoch}',
      name: copyName,
      preset: src.preset,
      colors: src.colors.copyWith(),
    );
    _customThemes.add(copy);
    _persistCustomThemes();
    notifyListeners();
    return copy.id;
  }

  /// Deletes a saved theme. If it was active, fall back to its base preset.
  void deleteCustomTheme(String id) {
    final i = _customThemes.indexWhere((t) => t.id == id);
    if (i == -1) return;
    final wasActive = _activeCustomId == id;
    final preset = _customThemes[i].preset;
    _customThemes.removeAt(i);
    if (wasActive) {
      _style = preset;
      _colors = DesignStylePalettes.of(preset);
      _activeCustomId = null;
    }
    _persistAll();
    notifyListeners();
  }

  /// Marks the first-launch picker as completed (Continue or Skip).
  void completeFirstLaunchPicker() {
    _pickerDone = true;
    StorageService.setSetting<bool>(true, key: 'theme.pickerDone');
    notifyListeners();
  }

  // --- persistence helpers (existing settings box) ---

  DesignStyle _loadStyle() {
    final raw = StorageService.getSetting<String?>('glassmorphism', key: 'theme.style');
    for (final s in DesignStyle.values) {
      if (s.name == raw) return s;
    }
    return DesignStyle.glassmorphism;
  }

  StyleColors _loadColors() {
    final raw = StorageService.getSetting<String?>(null, key: 'theme.colors');
    if (raw == null || raw.isEmpty) return DesignStylePalettes.of(_style);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return DesignStylePalettes.of(_style);
      return StyleColors.fromJson(
        Map<String, dynamic>.from(decoded),
        DesignStylePalettes.of(_style),
      );
    } catch (_) {
      return DesignStylePalettes.of(_style);
    }
  }

  List<CustomTheme> _loadCustomThemes() {
    final raw = StorageService.getSetting<String?>(null, key: 'theme.customThemes');
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final themes = <CustomTheme>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final t = CustomTheme.fromJson(Map<String, dynamic>.from(entry));
        if (t != null) themes.add(t);
      }
      return themes;
    } catch (_) {
      return [];
    }
  }

  void _persistColors() {
    StorageService.setSetting<String>(jsonEncode(_colors.toJson()), key: 'theme.colors');
  }

  void _persistCustomThemes() {
    StorageService.setSetting<String>(
      jsonEncode(_customThemes.map((t) => t.toJson()).toList()),
      key: 'theme.customThemes',
    );
  }

  void _persistAll() {
    StorageService.setSetting<String>(_style.name, key: 'theme.style');
    _persistColors();
    _persistCustomThemes();
    StorageService.setSetting<String?>(_activeCustomId, key: 'theme.activeCustomId');
  }
}
