import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AlbumArt extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final double borderRadius;
  final bool showShadow;
  final Widget? child;

  const AlbumArt({
    super.key,
    this.imageUrl,
    this.size = 280,
    this.borderRadius = AppColors.radiusL,
    this.showShadow = true,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: showShadow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: AppColors.elevatedShadow,
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => _buildPlaceholder(context),
        errorWidget: (context, url, error) => _buildError(context),
      );
    }
    return _buildGradient(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: SizedBox(
          width: size * 0.3,
          height: size * 0.3,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return _buildGradient(context);
  }

  Widget _buildGradient(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Vinyl grooves effect
          ...List.generate(4, (index) {
            final diameter = size * (0.8 - index * 0.15);
            return Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            );
          }),
          Icon(
            Icons.music_note,
            size: size * 0.25,
            color: Colors.white.withValues(alpha: 0.9),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class AlbumArtSmall extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const AlbumArtSmall({
    super.key,
    this.imageUrl,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return AlbumArt(
      imageUrl: imageUrl,
      size: size,
      borderRadius: AppColors.radiusS,
      showShadow: false,
    );
  }
}

class AlbumArtMini extends StatelessWidget {
  final String? imageUrl;

  const AlbumArtMini({
    super.key,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return AlbumArt(
      imageUrl: imageUrl,
      size: 48,
      borderRadius: AppColors.radiusS,
      showShadow: false,
    );
  }
}
