import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../ui_helpers.dart';
import 'directory_detail_screen.dart';
import 'home_shell.dart';

class DirectoryFavoritesScreen extends StatefulWidget {
  const DirectoryFavoritesScreen({super.key});

  @override
  State<DirectoryFavoritesScreen> createState() => _DirectoryFavoritesScreenState();
}

class _DirectoryFavoritesScreenState extends State<DirectoryFavoritesScreen> {
  List<dynamic> items = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppState>().loadDirectoryFavorites();
      if (mounted) {
        setState(() {
          items = data;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = AppState.userFriendlyError(e);
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Избранные организации')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? errorState(context: context, message: error!, onRetry: _load)
              : items.isEmpty
                  ? emptyState(
                      context: context,
                      title: 'Нет избранных организаций',
                      subtitle: 'Добавляйте организации из справочника',
                      icon: Icons.bookmark_border,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final item = items[i] as Map<String, dynamic>;
                          return Material(
                            color: Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => DirectoryDetailScreen(item: item)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      categoryLabels[item['category']] ?? '${item['category']}',
                                      style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(item['title'] as String, style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 17)),
                                    if (item['address'] != null) ...[
                                      const SizedBox(height: 6),
                                      Text('${item['address']}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
