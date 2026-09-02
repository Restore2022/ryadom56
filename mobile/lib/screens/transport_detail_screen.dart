import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_prompt.dart';
import '../responsive.dart';
import '../state/app_state.dart';
import '../time_format.dart';
import '../ui_helpers.dart';

class TransportDetailScreen extends StatefulWidget {
  const TransportDetailScreen({super.key, required this.item});

  final Map<String, dynamic> item;

  @override
  State<TransportDetailScreen> createState() => _TransportDetailScreenState();
}

class _TransportDetailScreenState extends State<TransportDetailScreen> {
  late Map<String, dynamic> item;
  bool togglingFavorite = false;
  bool reportingOutdated = false;
  @override
  void initState() {
    super.initState();
    item = Map<String, dynamic>.from(widget.item);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final id = item['id'];
      if (id is! int) return;
      final state = context.read<AppState>();
      state.trackTransportView(id);
      try {
        final fresh = await state.getTransportRoute(id);
        if (mounted) setState(() => item = fresh);
      } catch (_) {}
    });
  }

  String _fmtUpdated(String? iso) {
    return formatApiDate(iso, empty: '—');
  }

  Future<void> _reportOutdated() async {
    final id = item['id'];
    if (id is! int || reportingOutdated) return;
    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы сообщить об ошибке');
    if (!loggedIn || !mounted) return;
    setState(() => reportingOutdated = true);
    try {
      await context.read<AppState>().reportTransportOutdated(id);
      if (mounted) showAppSnack(context, 'Спасибо! Модераторы проверят расписание');
    } catch (e) {
      if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => reportingOutdated = false);
    }
  }

  Future<void> _call(String? phone) async {
    final cleaned = (phone ?? '').replaceAll(RegExp(r'[\s\-()]'), '');
    if (cleaned.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: cleaned));
  }
  Future<void> _toggleFavorite() async {
    final id = item['id'];
    if (id is! int) return;
    final loggedIn = await ensureLoggedIn(context, message: 'Войдите, чтобы сохранить маршрут в избранное');
    if (!loggedIn || !mounted) return;
    final state = context.read<AppState>();
    final was = state.isTransportFavorited(id, item: item);
    setState(() => togglingFavorite = true);
    try {
      final updated = await state.toggleTransportFavorite(id, currentlyFavorited: was);
      if (mounted) setState(() => item = updated);
    } catch (e) {
      if (mounted) showAppSnack(context, AppState.userFriendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => togglingFavorite = false);
    }
  }

  Widget _scheduleBlock(BuildContext context, String title, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Text(text, style: const TextStyle(height: 1.45, fontSize: 15)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    final nextDeparture = item['next_departure']?.toString();
    final fareText = item['fare_text']?.toString();
    final phone = item['phone']?.toString();
    final notes = item['notes']?.toString();
    final description = item['description']?.toString();
    final times = (item['times'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? [];
    final trips = <Map<String, dynamic>>[];
    final rawTrips = item['trips'];
    if (rawTrips is List) {
      for (final row in rawTrips) {
        if (row is Map) trips.add(Map<String, dynamic>.from(row));
      }
    }
    final weekdays = item['schedule_weekdays']?.toString();
    final weekends = item['schedule_weekends']?.toString();
    final schedule = item['schedule_text']?.toString() ?? '';
    final stops = (item['stops'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? [];
    final id = item['id'];
    final favorited = id is int && state.isTransportFavorited(id, item: item);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Маршрут'),
        actions: [
          IconButton(
            tooltip: favorited ? 'Убрать из избранного' : 'В избранное',
            onPressed: togglingFavorite ? null : _toggleFavorite,
            icon: Icon(
              favorited ? Icons.star : Icons.star_border,
              color: favorited ? scheme.primary : null,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: context.scrollPad(top: 8, bottom: 20),
        children: [
          Text(
            '${item['title']}',
            style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
          ),
          if (item['settlement_name'] != null) ...[
            const SizedBox(height: 8),
            Text('${item['settlement_name']}', style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 6),
          Text(
            'Обновлено: ${_fmtUpdated(item['updated_at']?.toString())}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          if (nextDeparture != null && nextDeparture.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ближайший рейс', style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12, fontWeight: FontWeight.w700)),
                        Text(nextDeparture, style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w800, fontSize: 16)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (fareText != null && fareText.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoLine(icon: Icons.payments_outlined, label: 'Стоимость', value: fareText),
          ],
          if (phone != null && phone.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoLine(icon: Icons.phone_outlined, label: 'Телефон', value: phone),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _call(phone),
              icon: const Icon(Icons.phone),
              label: const Text('Позвонить'),
            ),
          ],
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(description, style: const TextStyle(height: 1.4)),
          ],
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: togglingFavorite ? null : _toggleFavorite,
            icon: Icon(favorited ? Icons.star : Icons.star_border),
            label: Text(favorited ? 'В избранном' : 'В избранное'),
          ),
          if (stops.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Остановки', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            ...stops.asMap().entries.map(
              (e) {
                final last = e.key == stops.length - 1;
                final label = e.key == 0 ? 'откуда' : (last ? 'куда' : '${e.key + 1}');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 64,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.value, style: const TextStyle(height: 1.35))),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 20),
          if (trips.isNotEmpty) ...[
            Text('Рейсы', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            ...trips.map((trip) {
              final days = trip['days_label']?.toString() ?? '';
              final depart = trip['depart']?.toString() ?? '';
              final arrive = trip['arrive']?.toString();
              final stamp = (arrive != null && arrive.isNotEmpty) ? '$depart → $arrive' : depart;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          stamp,
                          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                      if (days.isNotEmpty)
                        Text(days, style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
              );
            }),
          ] else if (times.isNotEmpty) ...[
            Text('Отправления', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final stamp in times)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      stamp,
                      style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
              ],
            ),
          ] else ...[
            if (weekdays != null && weekdays.isNotEmpty) ...[
              _scheduleBlock(context, 'Будни', weekdays),
              const SizedBox(height: 16),
            ],
            if (weekends != null && weekends.isNotEmpty) ...[
              _scheduleBlock(context, 'Выходные', weekends),
              const SizedBox(height: 16),
            ],
            if (schedule.isNotEmpty) _scheduleBlock(context, 'Расписание', schedule),
          ],
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Важно', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            Text(notes, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: reportingOutdated ? null : _reportOutdated,
            icon: reportingOutdated
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.report_outlined),
            label: Text(reportingOutdated ? 'Отправка…' : 'Расписание устарело'),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
