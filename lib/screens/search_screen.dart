import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/discovery_service.dart';
import '../services/player_service.dart';
import '../services/storage_service.dart';
import '../models/song.dart';
import '../widgets/song_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.searchRemote});

  /// Remote search used for every query. Defaults to [DiscoveryService.search];
  /// tests inject a fake here so instant-search behavior is verifiable
  /// without network access.
  final Future<List<Song>> Function(String query)? searchRemote;

  /// Interval between the last keystroke and the fired search. Exposed for
  /// tests so they pump exactly to (and never past) the debounce boundary.
  @visibleForTesting
  static Duration get searchDebounce => _SearchScreenState._searchDebounce;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Song> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  List<String> _recentSearches = [];
  List<Song> _suggestedSongs = [];

  /// Interval between the last keystroke and the fired search. Long enough
  /// to batch real typing, short enough to feel instant.
  static const Duration _searchDebounce = Duration(milliseconds: 350);

  Timer? _debounceTimer;

  /// Monotonic id of the newest search request. Because search is fired on
  /// every keystroke with no debounce, responses race; a response whose id is
  /// no longer the newest must never land in [_results].
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  void _loadSuggestions() {
    _recentSearches = StorageService.getRecentSearches();
    _suggestedSongs = StorageService.getMostPlayed(limit: 5);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Fires a search for the current text immediately and guards against
  /// stale responses: only the result of the most recently issued search is
  /// applied, so fast typing can never let an older reply overwrite a newer
  /// one. Empty queries clear state synchronously.
  ///
  /// Recent searches are recorded on explicit submission only (keyboard
  /// search action / Enter) — never per keystroke, otherwise every partial
  /// query ("lo", "lof", "lofi"...) pollutes the recents list.
  Future<void> _search({bool record = false}) async {
    final query = _controller.text.trim();
    final seq = ++_searchSeq;
    if (query.isEmpty) {
      _debounceTimer?.cancel();
      setState(() {
        _results = [];
        _hasSearched = false;
        _isLoading = false;
      });
      return;
    }

    if (record) StorageService.addRecentSearch(query);
    setState(() {
      _recentSearches = StorageService.getRecentSearches();
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      final results =
          await (widget.searchRemote ?? DiscoveryService.search)(query);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = [];
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    // Debounce: batch keystrokes into one request after typing settles, so
    // "metallica" costs one round-trip instead of nine. The sequence guard
    // inside _search still protects against stragglers from earlier timers.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_searchDebounce, () => _search());
  }

  void _submitSearch(String query) {
    _focusNode.unfocus();
    _search(record: true);
  }

  void _tapRecentSearch(String query) {
    _controller.text = query;
    _focusNode.unfocus();
    _search(record: true);
  }

  void _removeRecentSearch(String query) async {
    await StorageService.removeRecentSearch(query);
    setState(() {
      _recentSearches.remove(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final showSuggestions = !_hasSearched && !_isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              // The typed text renders at the font's own line metrics instead
              // of the theme's forced 1.5x multiplier, so fallback-font glyphs
              // (emoji, accented characters) have full headroom inside the
              // field's line box and are never vertically clipped.
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: 1.0,
                    fontSize: 16,
                    fontFamily: 'Inter',
                  ),
              // Give the glyphs vertical slack inside the decorated border.
              // Material 3 sizes the field to exactly the text's preferred
              // line height (56 = 24 + 32 at scale 1.0), leaving no headroom;
              // devices that round pixel metrics then clip ascenders or
              // descenders of the typed text.
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 12,
                ),
                hintText: 'Search songs, artists...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _results = [];
                            _hasSearched = false;
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
              ),
              onChanged: _onSearchChanged,
              // Record a recent search only when the user explicitly
              // commits the query (Enter / IME search action).
              textInputAction: TextInputAction.search,
              onSubmitted: _submitSearch,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : showSuggestions
                    ? _buildSuggestions(context, playerService)
                    : _results.isEmpty
                        ? Center(
                            child: Text(
                              'No results found.',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              return SongCard(
                                song: _results[index],
                                onTap: () {
                                  playerService.play(_results[index]);
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context, PlayerService playerService) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (_recentSearches.isNotEmpty) ...[
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent searches',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () async {
                  await StorageService.clearRecentSearches();
                  setState(() {
                    _recentSearches = [];
                  });
                },
                child: const Text('Clear all'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recentSearches.map((query) {
              return GestureDetector(
                onTap: () => _tapRecentSearch(query),
                child: Chip(
                  label: Text(query),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () => _removeRecentSearch(query),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],
        if (_suggestedSongs.isNotEmpty) ...[
          const Text(
            'Suggested',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...(_suggestedSongs.asMap().entries.map((entry) {
            return SongCard(
              song: entry.value,
              onTap: () {
                playerService.play(entry.value);
              },
            );
          })),
        ],
        if (_recentSearches.isEmpty && _suggestedSongs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 64),
              child: Text(
                'Search for your favorite music.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
