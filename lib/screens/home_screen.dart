import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/player_service.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import '../models/song.dart';
import '../widgets/song_card.dart';
import '../widgets/update_dialog.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_container.dart';
import '../theme/app_colors.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'downloads_screen.dart';
import 'settings_screen.dart';
import '../widgets/mini_player.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  List<Song> _recentPlays = [];
  List<Song> _mostPlayed = [];
  List<Song> _favorites = [];

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  void _loadRecents() {
    setState(() {
      _recentPlays = StorageService.getRecentPlays();
      _mostPlayed = StorageService.getMostPlayed(limit: 10);
      _favorites = StorageService.getFavorites();
    });
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeContent(playerService),
          const SearchScreen(),
          const LibraryScreen(),
          const DownloadsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (playerService.currentSong != null) const MiniPlayer(),
          NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() => _currentIndex = index);
              if (index == 0) _loadRecents();
            },
            height: 72,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.search),
                selectedIcon: Icon(Icons.search),
                label: 'Search',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.download_outlined),
                selectedIcon: Icon(Icons.download),
                label: 'Downloads',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent(PlayerService playerService) {
    final updateService = context.watch<UpdateService>();

    // Ambient background wraps the whole scroll view so the charcoal +
    // violet lighting is continuous behind every section (§3) — the light
    // comes from the page, not from a banner.
    return AmbientBackground(
      child: CustomScrollView(
        slivers: [
          // Compact title row (§1/§2): plain AppBar, no expanded hero, no
          // gradient, no decorative shapes, no in-app logo image. The
          // launcher icon (Android manifest) is unaffected by this.
          SliverAppBar(
            pinned: true,
            toolbarHeight: 56,
            title: const Text(
              'CapuTune',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
            actions: [
              // Theme toggle kept compact: default 48dp tap target with a
              // tighter visual glyph, right-aligned as before.
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  playerService.isDarkMode
                      ? Icons.light_mode
                      : Icons.dark_mode,
                ),
                onPressed: () => playerService.toggleDarkMode(),
              ),
              const SizedBox(width: AppColors.spacingS),
            ],
          ),
          // Update banner (non-intrusive, dismissible)
          if (updateService.state == UpdateState.updateAvailable)
            SliverToBoxAdapter(
              child: _UpdateBanner(updateService: updateService),
            ),
        // Recently Played section
        SliverToBoxAdapter(
          child: _buildSection(
            title: 'Recently Played',
            songs: _recentPlays,
            emptyMessage:
                'No recent plays yet.\nStart listening to see your history!',
            playerService: playerService,
          ),
        ),
        // Most Played section
        SliverToBoxAdapter(
          child: _buildSection(
            title: 'Most Played',
            songs: _mostPlayed,
            emptyMessage:
                'No plays yet.\nStart listening to see your top songs!',
            playerService: playerService,
          ),
        ),
        // Favorites section
        if (_favorites.isNotEmpty)
          SliverToBoxAdapter(
            child: _buildSection(
              title: 'Favorites',
              songs: _favorites,
              emptyMessage: '',
              playerService: playerService,
            ),
          ),
      ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Song> songs,
    required String emptyMessage,
    required PlayerService playerService,
  }) {
    // Vertical rhythm: 8px above the heading, 8px heading→cards, and a 16px
    // bottom pad — so consecutive sections sit 24px apart with no dead band.
    // Content moves up into the space the old 180px banner reserved.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppColors.spacingL,
        AppColors.spacingS,
        AppColors.spacingL,
        AppColors.spacingM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (songs.isNotEmpty)
                TextButton(
                  // Compact "See all" keeps the heading row one visual line.
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {},
                  child: const Text('See all'),
                ),
            ],
          ),
          const SizedBox(height: AppColors.spacingS),
          if (songs.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppColors.spacingXL),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(AppColors.radiusL),
              ),
              child: Center(
                child: Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            // Artwork row: height derives from the card itself instead of a
            // fixed 220px box, so no space is reserved below the cards.
            SizedBox(
              height: SongCard.compactCardHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: songs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: AppColors.spacingM),
                    child: SongCard(
                      song: songs[index],
                      isCompact: true,
                      onTap: () {
                        playerService.playList(
                          songs,
                          startIndex: index,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// A dismissible, non-blocking banner shown on the Home tab when a newer
/// release is available. Tapping "Later" remembers the dismissal so the same
/// version is not shown again automatically.
class _UpdateBanner extends StatelessWidget {
  final UpdateService updateService;
  const _UpdateBanner({required this.updateService});

  @override
  Widget build(BuildContext context) {
    // Glass surface with opt-in background blur: this banner floats over
    // scrolling content, so it is one of the few justified BackdropFilters
    // (§3). Gradient container replaced with translucent glass + hairline.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppColors.spacingL,
        AppColors.spacingM,
        AppColors.spacingL,
        0,
      ),
      child: GlassContainer(
        blur: true,
        padding: const EdgeInsets.all(AppColors.spacingM),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppColors.spacingS),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppColors.radiusS),
              ),
              child: Icon(
                Icons.system_update,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppColors.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Update available',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppColors.spacingXS),
                  Text(
                    'Version ${updateService.latestVersion} is ready',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => updateService.dismissUpdate(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => showUpdateOffer(context, updateService),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }
}
