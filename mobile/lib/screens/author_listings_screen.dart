import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'home_shell.dart';
import 'listing_detail_screen.dart';

class AuthorListingsScreen extends StatefulWidget {
  const AuthorListingsScreen({
    super.key,
    required this.authorId,
    required this.authorName,
  });

  final int authorId;
  final String authorName;

  @override
  State<AuthorListingsScreen> createState() => _AuthorListingsScreenState();
}

class _AuthorListingsScreenState extends State<AuthorListingsScreen> {
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
      final data = await context.read<AppState>().loadAuthorListings(widget.authorId);
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
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.authorName)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : items.isEmpty
                  ? const Center(child: Text('Нет опубликованных объявлений'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final item = items[i] as Map<String, dynamic>;
                        final images = (item['images'] as List?) ?? [];
                        final thumb = images.isNotEmpty ? (images.first as Map)['url'] as String? : null;
                        return Material(
                          color: Theme.of(context).cardTheme.color,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.push(
                              context,
                              fastRoute(ListingDetailScreen(listingId: item['id'] as int, preview: item)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: thumb == null
                                        ? Container(
                                            width: 64,
                                            height: 64,
                                            color: scheme.surfaceContainerHighest,
                                            child: const Icon(Icons.image_outlined),
                                          )
                                        : Image.network(
                                            state.mediaUrl(thumb),
                                            width: 64,
                                            height: 64,
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item['title'] as String, style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 4),
                                        Text(
                                          categoryLabels[item['category']] ?? '${item['category']}',
                                          style: TextStyle(color: scheme.primary, fontSize: 12),
                                        ),
                                        if (item['price'] != null)
                                          Text('${item['price']} ₽', style: const TextStyle(fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
