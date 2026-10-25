import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/download_service.dart';
import '../services/player_service.dart';
import '../theme/app_colors.dart';
import 'add_to_playlist_dialog.dart';

class SongCard extends StatefulWidget {
  final Song song;
  final VoidCallback? onTap;
  final bool isCompact;

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
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
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
            width: 160,
            padding: const EdgeInsets.all(AppColors.spacingS),
            decoration: BoxDecoration(
              color: _isHovered
                  ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppColors.radiusM),
              boxShadow: _isHovered ? AppColors.cardShadow : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Album art with shadow
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppColors.radiusM),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: _isHovered ? 0.3 : 0.2),
                        blurRadius: _isHovered ? 16 : 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppColors.radiusM),
                    child: widget.song.thumbnail != null
                        ? CachedNetworkImage(
                            imageUrl: widget.song.thumbnail!,
                            width: 144,
                            height: 144,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              width: 144,
                              height: 144,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).colorScheme.primaryContainer,
                                    Theme.of(context).colorScheme.secondaryContainer,
                                  ],
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              width: 144,
                              height: 144,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.secondary,
                                  ],
                                ),
                              ),
                              child: const Icon(Icons.music_note, color: Colors.white),
                            ),
                          )
                        : Container(
                            width: 144,
                            height: 144,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary,
                                  Theme.of(context).colorScheme.secondary,
                                ],
                              ),
                            ),
                            child: const Icon(Icons.music_note, color: Colors.white),
                          ),
                  ),
                ),
                const SizedBox(height: AppColors.spacingS),
                Text(
                  widget.song.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppColors.spacingXS),
                Text(
                  widget.song.artist,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullCard(BuildContext context) {
    final downloadService = context.watch<DownloadService>();
    final isDownloading = downloadService.isDownloading(widget.song.id);
    final isDownloaded = downloadService.getState(widget.song.id) == DownloadState.downloaded;
    // ignore: unused_local_variable
    final isLocalFile = widget.song.localPath != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: AppColors.spacingS),
        child: Material(
          color: _isHovered
              ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppColors.radiusM),
          elevation: _isHovered ? 2 : 0,
          child: ListTile(
            contentPadding: const EdgeInsets.all(AppColors.spacingS),
            leading: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppColors.radiusS),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _isHovered ? 0.2 : 0.1),
                    blurRadius: _isHovered ? 8 : 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppColors.radiusS),
                child: widget.song.thumbnail != null
                    ? CachedNetworkImage(
                        imageUrl: widget.song.thumbnail!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 56,
                          height: 56,
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).colorScheme.primary,
                                Theme.of(context).colorScheme.secondary,
                              ],
                            ),
                          ),
                          child: const Icon(Icons.music_note, color: Colors.white),
                        ),
                      )
                    : Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).colorScheme.primary,
                              Theme.of(context).colorScheme.secondary,
                            ],
                          ),
                        ),
                        child: const Icon(Icons.music_note, color: Colors.white),
                      ),
              ),
            ),
            title: Text(
              widget.song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              widget.song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    color: Theme.of(context).colorScheme.primary,
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
              leading: const Icon(Icons.queue_music),
              title: const Text('Add to queue'),
              onTap: () {
                final added = context.read<PlayerService>().addToQueue(widget.song);
                Navigator.pop(sheetContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(added
                          ? 'Added "${widget.song.title}" to the queue.'
                          : 'That song is already in the queue.'),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Add to playlist'),
              onTap: () => Navigator.pop(sheetContext, 'add_to_playlist'),
            ),
            ListTile(
              leading: Icon(
                context.read<PlayerService>().isFavorite(widget.song.id)
                    ? Icons.favorite
                    : Icons.favorite_border,
              ),
              title: const Text('Add to favorites'),
              onTap: () {
                context.read<PlayerService>().toggleFavorite(widget.song);
                Navigator.pop(sheetContext);
              },
            ),
            if (isDownloaded || isLocalFile)
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: Text(isLocalFile ? 'Copy to Downloads' : 'Save to device (MP3)'),
                subtitle: Text(isLocalFile
                    ? 'Copy original audio file to Downloads folder'
                    : 'Export unencrypted MP3 to Downloads folder'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final path = await downloadService.saveToDevice(widget.song);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(path != null
                            ? 'Saved to Downloads folder'
                            : 'Failed to save to device'),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );

    if (action == 'add_to_playlist' && mounted) {
      await showAddToPlaylistDialog(this.context, widget.song);
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
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFavorite = context.read<PlayerService>().isFavorite(widget.song.id);

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
          color: isFavorite ? AppColors.accentPink : null,
          size: 20,
        ),
      ),
    );
  }
}
