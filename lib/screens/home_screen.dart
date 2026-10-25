import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/player_service.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import '../models/song.dart';
import '../widgets/song_card.dart';
import '../widgets/update_dialog.dart';
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

    return CustomScrollView(
      slivers: [
        // Hero header
        SliverAppBar(
          expandedHeight: 180,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            // Left-align the title block instead of FlexibleSpaceBar's
            // default 72dp toolbar indent, so the logo + app name line up
            // with the 24dp horizontal padding used by the content below.
            centerTitle: false,
            titlePadding: const EdgeInsetsDirectional.only(
              start: AppColors.spacingL,
              bottom: 14,
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/images/logo.jpg',
                    width: 28,
                    height: 28,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 8),
                // Flexible so a narrow screen ellipsizes instead of
                // overflowing the app bar.
                const Flexible(
                  child: Text(
                    'CapuTune',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF6C63FF),
                    Color(0xFF9C27B0),
                    Color(0xFFE91E63),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  // Decorative circles
                  Positioned(
                    top: -30,
                    right: -30,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -20,
                    left: -20,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  // Music note icon
                  Center(
                    child: Icon(
                      Icons.music_note_rounded,
                      size: 100,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                playerService.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                color: Colors.white,
              ),
              onPressed: () => playerService.toggleDarkMode(),
            ),
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
    );
  }

  Widget _buildSection({
    required String title,
    required List<Song> songs,
    required String emptyMessage,
    required PlayerService playerService,
  }) {
    // Vertical rhythm: 8px above the heading (plus the previous section's
    // 16px bottom padding = 24px between sections), 16px below before the
    // cards. This replaces the old uniform 24px padding which left a ~48px
    // dead band between sections.
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
                  onPressed: () {},
                  child: const Text('See all'),
                ),
            ],
          ),
          const SizedBox(height: AppColors.spacingM),
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
            SizedBox(
              height: 220,
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
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppColors.spacingL,
        AppColors.spacingM,
        AppColors.spacingL,
        0,
      ),
      padding: const EdgeInsets.all(AppColors.spacingM),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.secondaryContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(AppColors.radiusL),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppColors.spacingS),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
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
    );
  }
}
