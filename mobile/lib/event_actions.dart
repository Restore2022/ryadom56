import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _remindersKey = 'event_reminders';

String _fmtLocal(String? iso, {bool withTime = true}) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return iso;
  final d = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  if (!withTime) return d;
  return '$d, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

String _icsStamp(DateTime dt) {
  final u = dt.toUtc();
  return '${u.year.toString().padLeft(4, '0')}'
      '${u.month.toString().padLeft(2, '0')}'
      '${u.day.toString().padLeft(2, '0')}T'
      '${u.hour.toString().padLeft(2, '0')}'
      '${u.minute.toString().padLeft(2, '0')}'
      '${u.second.toString().padLeft(2, '0')}Z';
}

String _gcalStamp(DateTime dt) {
  final u = dt.toUtc();
  return '${u.year.toString().padLeft(4, '0')}'
      '${u.month.toString().padLeft(2, '0')}'
      '${u.day.toString().padLeft(2, '0')}T'
      '${u.hour.toString().padLeft(2, '0')}'
      '${u.minute.toString().padLeft(2, '0')}'
      '${u.second.toString().padLeft(2, '0')}Z';
}

Future<void> shareEvent(Map<String, dynamic> event) async {
  final title = event['title']?.toString() ?? 'Событие';
  final when = _fmtLocal(event['starts_at']?.toString());
  final place = event['place_text']?.toString() ?? '';
  final settlement = event['settlement_name']?.toString() ?? '';
  final loc = [place, if (settlement.isNotEmpty) settlement].where((e) => e.isNotEmpty).join(' · ');
  final text = [
    title,
    if (when.isNotEmpty) when,
    if (loc.isNotEmpty) loc,
    if ((event['description']?.toString() ?? '').isNotEmpty) event['description'].toString(),
  ].join('\n');
  await SharePlus.instance.share(ShareParams(text: text));
}

Future<void> addEventToCalendar(Map<String, dynamic> event) async {
  final title = event['title']?.toString() ?? 'Событие';
  final starts = DateTime.tryParse(event['starts_at']?.toString() ?? '');
  if (starts == null) {
    throw Exception('Не удалось определить дату события');
  }
  final ends = DateTime.tryParse(event['ends_at']?.toString() ?? '') ?? starts.add(const Duration(hours: 2));
  final place = [
    event['place_text']?.toString() ?? '',
    event['address']?.toString() ?? '',
  ].where((e) => e.isNotEmpty).join(', ');
  final description = event['description']?.toString() ?? '';

  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/event_${event['id'] ?? 'ryadom'}.ics');
    final body = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Ryadom56//Event//RU',
      'BEGIN:VEVENT',
      'UID:ryadom56-event-${event['id'] ?? title.hashCode}@ryadom56',
      'DTSTAMP:${_icsStamp(DateTime.now())}',
      'DTSTART:${_icsStamp(starts)}',
      'DTEND:${_icsStamp(ends)}',
      'SUMMARY:${title.replaceAll('\n', ' ')}',
      if (description.isNotEmpty) 'DESCRIPTION:${description.replaceAll('\n', '\\n')}',
      if (place.isNotEmpty) 'LOCATION:${place.replaceAll('\n', ' ')}',
      'END:VEVENT',
      'END:VCALENDAR',
      '',
    ].join('\r\n');
    await file.writeAsString(body, flush: true);
    final result = await OpenFilex.open(file.path);
    if (result.type == ResultType.done || result.type == ResultType.noAppToOpen) {
      if (result.type == ResultType.done) return;
    }
  } catch (_) {}

  final uri = Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': '${_gcalStamp(starts)}/${_gcalStamp(ends)}',
    if (description.isNotEmpty) 'details': description,
    if (place.isNotEmpty) 'location': place,
  });
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw Exception('Не удалось открыть календарь');
  }
}

Future<List<Map<String, dynamic>>> _readReminders(SharedPreferences prefs) async {
  final raw = prefs.getString(_remindersKey);
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  } catch (_) {
    return [];
  }
}

Future<void> _writeReminders(SharedPreferences prefs, List<Map<String, dynamic>> items) async {
  await prefs.setString(_remindersKey, jsonEncode(items));
}

/// Stores a local reminder for the calendar day before [starts_at].
Future<String> remindEventTomorrow(Map<String, dynamic> event) async {
  final id = event['id'];
  if (id is! int) throw Exception('Событие без id');
  final starts = DateTime.tryParse(event['starts_at']?.toString() ?? '')?.toLocal();
  if (starts == null) throw Exception('Не удалось определить дату события');
  final remindOn = DateTime(starts.year, starts.month, starts.day).subtract(const Duration(days: 1));
  final today = DateTime.now();
  final todayDay = DateTime(today.year, today.month, today.day);
  if (remindOn.isBefore(todayDay)) {
    throw Exception('Слишком поздно для напоминания «завтра»');
  }

  final prefs = await SharedPreferences.getInstance();
  final items = await _readReminders(prefs);
  items.removeWhere((e) => e['id'] == id);
  items.add({
    'id': id,
    'title': event['title']?.toString() ?? 'Событие',
    'starts_at': event['starts_at']?.toString(),
    'remind_on':
        '${remindOn.year.toString().padLeft(4, '0')}-${remindOn.month.toString().padLeft(2, '0')}-${remindOn.day.toString().padLeft(2, '0')}',
  });
  await _writeReminders(prefs, items);
  return _fmtLocal(starts.toIso8601String(), withTime: false);
}

Future<List<Map<String, dynamic>>> dueEventRemindersToday() async {
  final prefs = await SharedPreferences.getInstance();
  final items = await _readReminders(prefs);
  final now = DateTime.now();
  final today =
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return items.where((e) => e['remind_on']?.toString() == today).toList();
}

Future<void> dismissEventReminder(int id) async {
  final prefs = await SharedPreferences.getInstance();
  final items = await _readReminders(prefs);
  items.removeWhere((e) => e['id'] == id);
  await _writeReminders(prefs, items);
}

Future<void> checkAndShowEventReminders(BuildContext context) async {
  final due = await dueEventRemindersToday();
  for (final item in due) {
    if (!context.mounted) return;
    final title = item['title']?.toString() ?? 'Событие';
    final when = _fmtLocal(item['starts_at']?.toString());
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Напоминание'),
        content: Text(
          when.isEmpty
              ? 'Напоминание: завтра событие «$title»'
              : 'Напоминание: завтра событие «$title» ($when)',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
        ],
      ),
    );
    final id = item['id'];
    if (id is int) await dismissEventReminder(id);
  }
}
