/// Время с API: UTC. Строка без пояса (SQLite) иначе читается как местная.
DateTime? parseApiTime(String? iso) {
  if (iso == null) return null;
  var s = iso.trim();
  if (s.isEmpty) return null;
  s = s.replaceFirst(' ', 'T');
  final hasTz = s.endsWith('Z') || s.endsWith('z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
  if (!hasTz) s = '${s}Z';
  return DateTime.tryParse(s)?.toLocal();
}

String _two(int n) => n.toString().padLeft(2, '0');

String formatDateTimeLocal(DateTime dt, {bool withTime = true}) {
  final d = '${_two(dt.day)}.${_two(dt.month)}.${dt.year}';
  if (!withTime) return d;
  return '$d, ${_two(dt.hour)}:${_two(dt.minute)}';
}

String formatApiDate(String? iso, {String empty = ''}) {
  final dt = parseApiTime(iso);
  if (dt == null) return empty;
  return formatDateTimeLocal(dt, withTime: false);
}

String formatApiDateTime(String? iso, {String empty = '', String sep = ' · '}) {
  final dt = parseApiTime(iso);
  if (dt == null) return empty;
  return '${_two(dt.day)}.${_two(dt.month)}.${dt.year}$sep${_two(dt.hour)}:${_two(dt.minute)}';
}

String formatApiClock(String? iso, {String empty = ''}) {
  final dt = parseApiTime(iso);
  if (dt == null) return empty;
  return '${_two(dt.hour)}:${_two(dt.minute)}';
}

String formatApiRelative(String? iso, {String empty = ''}) {
  final dt = parseApiTime(iso);
  if (dt == null) return empty;
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.isNegative || diff.inMinutes < 1) return 'только что';
  if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
  if (diff.inHours < 24 && now.year == dt.year && now.month == dt.month && now.day == dt.day) {
    return '${diff.inHours} ч назад';
  }
  final days = diff.inDays < 1 ? 1 : diff.inDays;
  if (days < 7) return '$days дн назад';
  return formatDateTimeLocal(dt, withTime: false);
}

String formatApiChatList(String? iso, {String empty = ''}) {
  final dt = parseApiTime(iso);
  if (dt == null) return empty;
  final now = DateTime.now();
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return '${_two(dt.hour)}:${_two(dt.minute)}';
  }
  return '${_two(dt.day)}.${_two(dt.month)}';
}

String formatApiMonthYear(String? iso, {String empty = ''}) {
  final dt = parseApiTime(iso);
  if (dt == null) return empty;
  return 'с ${_two(dt.month)}.${dt.year}';
}

const _monthsGen = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

/// «15 сентября, 17:00–18:00» — когда будет и с какого часа до какого.
String formatEventWhen(String? startIso, String? endIso) {
  final start = parseApiTime(startIso);
  if (start == null) return '';
  final date = '${start.day} ${_monthsGen[start.month - 1]}';
  final t1 = '${_two(start.hour)}:${_two(start.minute)}';
  final end = parseApiTime(endIso);
  if (end == null) return '$date, $t1';
  final t2 = '${_two(end.hour)}:${_two(end.minute)}';
  final sameDay = start.year == end.year && start.month == end.month && start.day == end.day;
  if (sameDay) return '$date, $t1–$t2';
  return '$date, $t1 — ${end.day} ${_monthsGen[end.month - 1]}, $t2';
}
