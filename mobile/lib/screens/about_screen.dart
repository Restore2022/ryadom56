import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../responsive.dart';
import '../update_service.dart';
import 'home_shell.dart';
import 'legal_doc_screen.dart';

const supportPhone = '+79083211801';
const supportEmail = 'info@legac.ru';
const publicSite = 'https://legac.ru';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String versionLabel = '…';
  bool checking = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => versionLabel = '${info.version}+${info.buildNumber}');
    });
  }

  Future<void> _call() async {
    final uri = Uri(scheme: 'tel', path: supportPhone);
    await launchUrl(uri);
  }

  Future<void> _mail() async {
    final uri = Uri(scheme: 'mailto', path: supportEmail);
    await launchUrl(uri);
  }

  Future<void> _openSite() async {
    await launchUrl(Uri.parse(publicSite), mode: LaunchMode.externalApplication);
  }

  Future<void> _checkUpdates() async {
    setState(() => checking = true);
    try {
      await checkForAppUpdate(context, manual: true);
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('О проекте')),
      body: ListView(
        padding: context.scrollPad(left: 20, top: 20, right: 20, bottom: 20),
        children: [
          Text(
            'Рядом56',
            style: GoogleFonts.unbounded(fontSize: 28, fontWeight: FontWeight.w700, color: scheme.primary),
          ),
          const SizedBox(height: 8),
          Text(
            'Версия $versionLabel',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Text(
            'Локальные объявления и справочник для жителей Оренбургской области. '
            'Здесь можно найти товары рядом, услуги, работу, аренду и полезные '
            'контакты школ, больниц, магазинов и других организаций.',
            style: GoogleFonts.manrope(fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            onPressed: checking ? null : _checkUpdates,
            icon: checking
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.system_update_alt),
            label: Text(checking ? 'Проверка…' : 'Проверить обновления'),
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
          const SizedBox(height: 10),
          Material(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _mail,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.mail_outline, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Почта', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                          Text(
                            supportEmail,
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
          const SizedBox(height: 10),
          Material(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _openSite,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.language, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Сайт', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                          Text(
                            'legac.ru',
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
            'Нажмите телефон, почту или сайт — откроется звонок, письмо или браузер.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
