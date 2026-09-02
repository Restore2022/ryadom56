import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../responsive.dart';
import '../state/app_state.dart';

class LegalDocScreen extends StatefulWidget {
  const LegalDocScreen({super.key, required this.slug, this.title});

  final String slug;
  final String? title;

  @override
  State<LegalDocScreen> createState() => _LegalDocScreenState();
}

class _LegalDocScreenState extends State<LegalDocScreen> {
  Map<String, dynamic>? doc;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AppState>().getLegalDoc(widget.slug);
      if (mounted) {
        setState(() {
          doc = data;
          loading = false;
          error = null;
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
    final title = doc?['title'] as String? ?? widget.title ?? 'Документ';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!)))
              : ListView(
                  padding: context.scrollPad(left: 20, top: 12, right: 20, bottom: 20),
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.unbounded(fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                    if (doc?['version'] != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Версия ${doc!['version']}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      (doc?['body'] as String?) ?? '',
                      style: GoogleFonts.manrope(fontSize: 15, height: 1.55),
                    ),
                  ],
                ),
    );
  }
}
