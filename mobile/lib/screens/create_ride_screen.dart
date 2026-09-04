import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../responsive.dart';
import '../ride_text.dart';
import '../settlement_picker.dart';
import '../state/app_state.dart';
import '../time_format.dart';
import '../ui_helpers.dart';

class CreateRideScreen extends StatefulWidget {
  const CreateRideScreen({super.key, this.initialKind = 'drive', this.fromSettlementId});

  final String initialKind;
  final int? fromSettlementId;

  @override
  State<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends State<CreateRideScreen> {
  late String kind;
  int? fromId;
  int? toId;
  DateTime depart = _defaultDepart();
  int seats = 2;
  final note = TextEditingController();
  bool busy = false;
  String? error;

  static DateTime _defaultDepart() {
    final now = DateTime.now();
    if (now.hour >= 20) {
      return DateTime(now.year, now.month, now.day + 1, 7, 0);
    }
    final hour = (now.minute > 10 ? now.hour + 1 : now.hour).clamp(5, 22);
    return DateTime(now.year, now.month, now.day, hour, 0);
  }

  @override
  void initState() {
    super.initState();
    kind = widget.initialKind == 'need' ? 'need' : 'drive';
    seats = kind == 'need' ? 1 : 2;
    final user = context.read<AppState>().user;
    fromId = widget.fromSettlementId ?? user?['settlement_id'] as int?;
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: depart,
      firstDate: DateTime.now().subtract(const Duration(days: 0)),
      lastDate: DateTime.now().add(const Duration(days: 14)),
      helpText: 'Когда выезжаете',
      cancelText: 'Отмена',
      confirmText: 'Дальше',
    );
    if (picked == null || !mounted) return;
    setState(() {
      depart = DateTime(picked.year, picked.month, picked.day, depart.hour, depart.minute);
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(depart),
      helpText: 'Во сколько',
      cancelText: 'Отмена',
      confirmText: 'Ок',
      hourLabelText: 'Часы',
      minuteLabelText: 'Минуты',
    );
    if (picked == null || !mounted) return;
    setState(() {
      depart = DateTime(depart.year, depart.month, depart.day, picked.hour, picked.minute);
    });
  }

  Future<void> _submit() async {
    if (fromId == null || toId == null) {
      setState(() => error = 'Укажите, откуда и куда');
      return;
    }
    if (fromId == toId) {
      setState(() => error = 'Откуда и куда — разные сёла');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await context.read<AppState>().createRide(
            kind: kind,
            fromSettlementId: fromId!,
            toSettlementId: toId!,
            departAt: depart,
            seats: seats,
            note: note.text,
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = AppState.userFriendlyError(e);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settlements = context.watch<AppState>().settlements;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(kind == 'need' ? 'Ищу попутку' : 'Еду')),
      body: ListView(
        padding: context.scrollPad(top: 16, bottom: 24),
        children: [
          Row(
            children: [
              Expanded(
                child: kind == 'drive'
                    ? FilledButton(onPressed: () {}, child: const Text('Еду'))
                    : OutlinedButton(
                        onPressed: () => setState(() {
                          kind = 'drive';
                          if (seats < 1) seats = 2;
                        }),
                        child: const Text('Еду'),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: kind == 'need'
                    ? FilledButton(onPressed: () {}, child: const Text('Ищу'))
                    : OutlinedButton(
                        onPressed: () => setState(() {
                          kind = 'need';
                          if (seats > 3) seats = 1;
                        }),
                        child: const Text('Ищу'),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettlementPicker(
            label: 'Откуда',
            value: fromId,
            settlements: settlements,
            onChanged: (v) => setState(() => fromId = v),
          ),
          Align(
            child: IconButton(
              tooltip: 'Поменять местами',
              onPressed: () => setState(() {
                final a = fromId;
                fromId = toId;
                toId = a;
              }),
              icon: const Icon(Icons.swap_vert),
            ),
          ),
          SettlementPicker(
            label: 'Куда',
            value: toId,
            settlements: settlements,
            onChanged: (v) => setState(() => toId = v),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _pickDate,
                  child: Text(formatDateTimeLocal(depart, withTime: false)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _pickTime,
                  child: Text(
                    '${depart.hour.toString().padLeft(2, '0')}:${depart.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(kind == 'need' ? 'Сколько человек' : 'Свободных мест', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: seats > 1 ? () => setState(() => seats--) : null,
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  rideSeatsLabel(kind, seats),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              IconButton.filledTonal(
                onPressed: seats < 8 ? () => setState(() => seats++) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: note,
            maxLength: 400,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Комментарий, если нужно',
              hintText: 'Через Переволоцкий, 200 ₽ с человека…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Это договорённость между людьми, не такси. Денег в приложении нет — как договоритесь в чате.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35, fontSize: 13),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: TextStyle(color: scheme.error, height: 1.35)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : _submit,
            child: busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(kind == 'need' ? 'Ищу попутку' : 'Поеду'),
          ),
        ],
      ),
    );
  }
}
