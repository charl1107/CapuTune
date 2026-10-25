import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/discovery_service.dart';
import '../services/player_service.dart';
import '../services/storage_service.dart';
import '../models/song.dart';
import '../widgets/song_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Song> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  Timer? _debounce;
  List<String> _recentSearches = [];
  List<Song> _suggestedSongs = [];

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
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _search();
    });
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    StorageService.addRecentSearch(query);
    _recentSearches = StorageService.getRecentSearches();

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    final results = await DiscoveryService.search(query);
    if (mounted) {
      setState(() {
        _results = results;
        _isLoading = false;
      });
    }
  }

  void _tapRecentSearch(String query) {
    _controller.text = query;
    _focusNode.unfocus();
    _search();
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
              decoration: InputDecoration(
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
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : showSuggestions
                    ? _buildSuggestions(context, playerService)
                    : _results.isEmpty
                        ? const Center(
                            child: Text(
                              'No results found.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              return SongCard(
                                song: _results[index],
                                onTap: () {
                                  playerService.playList(
                                    _results,
                                    startIndex: index,
                                  );
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent searches',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
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
                playerService.playList(
                  _suggestedSongs,
                  startIndex: entry.key,
                );
              },
            );
          })),
        ],
        if (_recentSearches.isEmpty && _suggestedSongs.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.only(top: 64),
              child: Text(
                'Search for your favorite music.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ),
      ],
    );
  }
}
