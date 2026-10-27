import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/download_service.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../theme/app_colors.dart';
import 'add_to_playlist_dialog.dart';

class SongCard extends StatefulWidget {
  final Song song;
  final VoidCallback? onTap;
  final bool isCompact;

  /// Compact (home screen) card metrics. The original card was 160dp wide
  /// with 144dp art inside a 220dp row; the compact card is much smaller on
  /// every axis: 104dp card, 88dp artwork, 146dp row (three cards fit on a
  /// typical 390-412dp phone). [compactArtwork] steps down 12dp on narrow
  /// screens and up 12dp on tablets via [_buildCompactCard].
  static const double compactCardHeight = 146;
  static const double compactArtwork = 104;

  const SongCard({
    super.key,
    required this.song,
    this.onTap,
    this.isCompact = false,
  });

  @override
  State<SongCard> createState() => _SongCardState();
}

class _SongCardState extends State<SongCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCompact) {
      return _buildCompactCard(context);
    }
    return _buildFullCard(context);
  }

  Widget _buildCompactCard(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final tokens = themeService.colors;

    final media = MediaQuery.of(context);
    final edge = media.size.width < 340
        ? SongCard.compactArtwork - 12
        : media.size.width > 700
            ? SongCard.compactArtwork + 12
            : SongCard.compactArtwork;
    final artSize = edge - 2 * AppColors.spacingS;

    // Distinct decorations per style for compact cards
    BoxDecoration cardDecoration;
    if (tokens.useHardShadow) {
      // Neo-brutalism: solid card with thick border and sharp drop shadow
      cardDecoration = BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius.clamp(2.0, 8.0)),
        border: Border.all(
          color: tokens.border,
          width: tokens.borderWidth.clamp(1.5, 3.0),
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.border,
            offset: _isHovered ? const Offset(4, 4) : const Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      );
    } else if (tokens.useNeonGlow) {
      // Cyberpunk / Neon: high contrast dark card with neon border & glow
      cardDecoration = BoxDecoration(
        color: tokens.card.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(tokens.radius),
        border: Border.all(
          color: _isHovered ? tokens.highlight : tokens.border,
          width: tokens.borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.glow.withValues(alpha: _isHovered ? 0.45 : 0.25),
            blurRadius: _isHovered ? 10 : 6,
          ),
        ],
      );
    } else if (tokens.useBlur) {
      // Glassmorphism: translucent gradient fill + hairline glass border
      cardDecoration = BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tokens.card.withValues(alpha: 0.70),
            tokens.surface.withValues(alpha: 0.82),
          ],
        ),
        borderRadius: BorderRadius.circular(tokens.radius),
        border: Border.all(
          color: tokens.border,
          width: tokens.borderWidth,
        ),
        boxShadow: _isHovered ? AppColors.cardShadow : null,
      );
    } else {
      // Ambient UI / Premium UI: Smooth card with subtle elevation / ambient glow
      cardDecoration = BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius),
        border: Border.all(
          color: tokens.border,
          width: tokens.borderWidth,
        ),
        boxShadow: [
          if (_isHovered)
            BoxShadow(
              color: Colors.black.withValues(alpha: tokens.isDark ? 0.3 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          if (tokens.glowStrength > 0.8)
            BoxShadow(
              color: tokens.glow.withValues(alpha: 0.12 * tokens.glowStrength),
              blurRadius: 10,
            ),
        ],
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) {
          _controller.reverse();
          widget.onTap?.call();
        },
        onTapCancel: () => _controller.reverse(),
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: edge,
            padding: const EdgeInsets.all(AppColors.spacingS),
            decoration: cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Artwork is bounded by the card's remaining height rather
                // than a fixed square: a thicker preset border (neo) or a
                // wide (tablet/desktop) card would otherwise push the title
                // and artist out of the card and paint an overflow stripe.
                // A loose Flexible lets the square shrink only when the
                // height demands it; on phones the width still wins, so the
                // common mobile layout is unchanged.
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      tokens.useHardShadow
                          ? 2.0
                          : (tokens.radius * 0.5).clamp(4.0, 10.0),
                    ),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: widget.song.thumbnail != null
                          ? CachedNetworkImage(
                              imageUrl: widget.song.thumbnail!,
                              width: artSize,
                              height: artSize,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                width: artSize,
                                height: artSize,
                                color: tokens.surface,
                              ),
                              errorWidget: (context, url, error) => Container(
                                width: artSize,
                                height: artSize,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [tokens.accent, tokens.highlight],
                                  ),
                                ),
                                child: const Icon(Icons.music_note,
                                    color: Colors.white),
                              ),
                            )
                          : Container(
                              width: artSize,
                              height: artSize,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [tokens.accent, tokens.highlight],
                                ),
                              ),
                              child: const Icon(Icons.music_note,
                                  color: Colors.white),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: AppColors.spacingXS),
                Text(
                  widget.song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: tokens.textPrimary,
                  ),
                ),
                Text(
                  widget.song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullCard(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final tokens = themeService.colors;

    final downloadService = context.watch<DownloadService>();
    final isDownloading = downloadService.isDownloading(widget.song.id);
    final isDownloaded = downloadService.getState(widget.song.id) == DownloadState.downloaded;
    final isRecommended = widget.song.isRecommended;

    BoxDecoration listDecoration;
    if (tokens.useHardShadow) {
      listDecoration = BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius.clamp(2.0, 8.0)),
        border: Border.all(
          color: tokens.border,
          width: tokens.borderWidth.clamp(1.5, 3.0),
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.border,
            offset: _isHovered ? const Offset(3, 3) : const Offset(2, 2),
            blurRadius: 0,
          ),
        ],
      );
    } else if (tokens.useNeonGlow) {
      listDecoration = BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius),
        border: Border.all(
          color: _isHovered ? tokens.highlight : tokens.border.withValues(alpha: 0.6),
          width: tokens.borderWidth,
        ),
        boxShadow: _isHovered
            ? [
                BoxShadow(
                  color: tokens.glow.withValues(alpha: 0.3),
                  blurRadius: 8,
                ),
              ]
            : null,
      );
    } else if (tokens.useBlur) {
      listDecoration = BoxDecoration(
        color: tokens.card.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(tokens.radius),
        border: Border.all(
          color: tokens.border,
          width: tokens.borderWidth,
        ),
      );
    } else {
      listDecoration = BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius),
        border: Border.all(
          color: tokens.border,
          width: tokens.borderWidth,
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: AppColors.spacingS),
        decoration: listDecoration,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(tokens.radius),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppColors.spacingM,
              vertical: 2,
            ),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(
                tokens.useHardShadow ? 2.0 : (tokens.radius * 0.4).clamp(4.0, 8.0),
              ),
              child: widget.song.thumbnail != null
                  ? CachedNetworkImage(
                      imageUrl: widget.song.thumbnail!,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 52,
                        height: 52,
                        color: tokens.surface,
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [tokens.accent, tokens.highlight],
                          ),
                        ),
                        child: const Icon(Icons.music_note, color: Colors.white),
                      ),
                    )
                  : Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [tokens.accent, tokens.highlight],
                        ),
                      ),
                      child: const Icon(Icons.music_note, color: Colors.white),
                    ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                if (isRecommended) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: tokens.accent.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      'SIMILAR',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: tokens.accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              widget.song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 12,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.song.duration != null)
                  Padding(
                    padding: const EdgeInsets.only(right: AppColors.spacingS),
                    child: Text(
                      widget.song.duration!,
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                if (isDownloading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (isDownloaded)
                  Icon(
                    Icons.download_done,
                    size: 20,
                    color: tokens.accent,
                  ),
                const SizedBox(width: AppColors.spacingXS),
                _FavoriteButton(song: widget.song),
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onPressed: () => _showOptions(context),
                ),
              ],
            ),
            onTap: widget.onTap,
          ),
        ),
      ),
    );
  }

  Future<void> _showOptions(BuildContext context) async {
    final downloadService = context.read<DownloadService>();
    final isDownloaded =
        downloadService.getState(widget.song.id) == DownloadState.downloaded;
    final isLocalFile = widget.song.localPath != null;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Add to playlist'),
              onTap: () => Navigator.pop(sheetContext, 'add_to_playlist'),
            ),
            if (!isLocalFile)
              ListTile(
                leading: Icon(
                  isDownloaded ? Icons.delete_outline : Icons.download,
                  color: isDownloaded ? Colors.red : null,
                ),
                title: Text(isDownloaded ? 'Delete download' : 'Download'),
                onTap: () => Navigator.pop(
                  sheetContext,
                  isDownloaded ? 'delete_download' : 'download',
                ),
              ),
          ],
        ),
      ),
    );

    if (!context.mounted || action == null) return;

    switch (action) {
      case 'add_to_playlist':
        showAddToPlaylistDialog(context, widget.song);
        break;
      case 'download':
        downloadService.downloadSong(widget.song);
        break;
      case 'delete_download':
        downloadService.removeDownload(widget.song.id);
        break;
    }
  }
}

class _FavoriteButton extends StatefulWidget {
  final Song song;
  const _FavoriteButton({required this.song});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final tokens = context.watch<ThemeService>().colors;
    final isFavorite = playerService.isFavorite(widget.song.id);

    return GestureDetector(
      onTap: () {
        context.read<PlayerService>().toggleFavorite(widget.song);
        if (!isFavorite) {
          _controller.forward().then((_) => _controller.reverse());
        }
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          color: isFavorite ? tokens.highlight : null,
          size: 20,
        ),
      ),
    );
  }
}
