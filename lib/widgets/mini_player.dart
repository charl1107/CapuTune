import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../screens/player_screen.dart';
import '../theme/app_colors.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final song = playerService.currentSong;
    final tokens = context.watch<ThemeService>().colors;

    if (song == null) return const SizedBox.shrink();

    // Distinct decorations per style for the miniplayer
    BoxDecoration containerDecoration;
    if (tokens.useHardShadow) {
      containerDecoration = BoxDecoration(
        color: tokens.surface,
        border: Border(
          top: BorderSide(
            color: tokens.border,
            width: tokens.borderWidth.clamp(1.5, 3.0),
          ),
        ),
      );
    } else if (tokens.useNeonGlow) {
      containerDecoration = BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: tokens.border,
            width: tokens.borderWidth,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.glow.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      );
    } else {
      containerDecoration = BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tokens.surface.withValues(alpha: tokens.useBlur ? 0.75 : 0.92),
            tokens.card.withValues(alpha: tokens.useBlur ? 0.70 : 0.96),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          top: BorderSide(
            color: tokens.border,
            width: tokens.borderWidth,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      );
    }

    Widget content = Container(
      height: 72,
      decoration: containerDecoration,
      child: Row(
        children: [
          const SizedBox(width: AppColors.spacingM),
          // Album art with shadow
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                tokens.useHardShadow ? 2.0 : (tokens.radius * 0.4).clamp(4.0, 8.0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                tokens.useHardShadow ? 2.0 : (tokens.radius * 0.4).clamp(4.0, 8.0),
              ),
              child: song.thumbnail != null
                  ? CachedNetworkImage(
                      imageUrl: song.thumbnail!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 48,
                        height: 48,
                        color: tokens.card,
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [tokens.accent, tokens.highlight],
                          ),
                        ),
                        child: const Icon(Icons.music_note, color: Colors.white),
                      ),
                    )
                  : Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [tokens.accent, tokens.highlight],
                        ),
                      ),
                      child: const Icon(Icons.music_note, color: Colors.white),
                    ),
            ),
          ),
          const SizedBox(width: AppColors.spacingM),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppColors.spacingXS),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Play/Pause button
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                playerService.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(playerService.isPlaying),
                color: tokens.accent,
              ),
            ),
            onPressed: () => playerService.togglePlay(),
          ),
          // Next button
          IconButton(
            icon: Icon(
              Icons.skip_next_rounded,
              color: tokens.textPrimary,
            ),
            onPressed: () => playerService.playNext(),
          ),
          const SizedBox(width: AppColors.spacingS),
        ],
      ),
    );

    if (tokens.useBlur) {
      content = ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: content,
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const PlayerScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                )),
                child: child,
              );
            },
          ),
        );
      },
      child: content,
    );
  }
}
