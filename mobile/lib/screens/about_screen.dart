import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'home_shell.dart';
import 'legal_doc_screen.dart';

const supportPhone = '+79083211801';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _call() async {
    final uri = Uri(scheme: 'tel', path: supportPhone);
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('О проекте')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Рядом56',
            style: GoogleFonts.unbounded(fontSize: 28, fontWeight: FontWeight.w700, color: scheme.primary),
          ),
          const SizedBox(height: 12),
          Text(
            'Локальные объявления и справочник для жителей Сакмарского района. '
            'Здесь можно найти товары рядом, услуги, работу, аренду и полезные '
            'контакты школ, больниц, магазинов и других организаций района.',
            style: GoogleFonts.manrope(fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 28),
          Text('Поддержка', style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Material(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _call,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.phone, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Телефон поддержки', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                          Text(
                            supportPhone,
                            style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.primary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text('Документы', style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Пользовательское соглашение'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              fastRoute(const LegalDocScreen(slug: 'terms', title: 'Пользовательское соглашение')),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Политика конфиденциальности'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              fastRoute(const LegalDocScreen(slug: 'privacy', title: 'Политика конфиденциальности')),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Правила объявлений'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              fastRoute(const LegalDocScreen(slug: 'listing_rules', title: 'Правила размещения объявлений')),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Нажмите на номер, чтобы позвонить.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
