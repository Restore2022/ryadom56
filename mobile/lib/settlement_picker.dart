import 'package:flutter/material.dart';

import 'responsive.dart';

const kPlaceLabel = 'Посёлок, село или город';
const kPlaceFindHint = 'Найти посёлок, село или город';
const kPlacePickPlease = 'Выберите посёлок, село или город';
const kPlaceNotInList = 'Такого места в списке нет';
const kPlaceTypeHint = 'Начните вводить название';

class SettlementPicker extends StatelessWidget {
  const SettlementPicker({
    super.key,
    required this.value,
    required this.settlements,
    required this.onChanged,
    this.label = kPlaceLabel,
    this.allowAll = false,
    this.allLabel = 'Все объявления',
    this.dense = false,
  });

  final int? value;
  final List<dynamic> settlements;
  final ValueChanged<int?> onChanged;
  final String label;
  final bool allowAll;
  final String allLabel;
  final bool dense;

  String _nameOf(int? id) {
    if (id == null) return allowAll ? allLabel : '';
    for (final s in settlements) {
      if (s is Map && s['id'] == id) return '${s['display_name'] ?? ''}';
    }
    return '';
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showSettlementSearch(
      context,
      settlements: settlements,
      selectedId: value,
      allowAll: allowAll,
      allLabel: allLabel,
    );
    if (!context.mounted || picked == null) return;
    onChanged(picked.id);
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameOf(value);
    return TextFormField(
      key: ValueKey<String>('place-${value ?? 'none'}-$name-$dense'),
      initialValue: name,
      readOnly: true,
      enableInteractiveSelection: false,
      onTap: () => _open(context),
      maxLines: 1,
      style: const TextStyle(overflow: TextOverflow.ellipsis),
      decoration: InputDecoration(
        isDense: dense,
        labelText: label,
        hintText: kPlaceFindHint,
        hintMaxLines: 1,
        prefixIcon: const Icon(Icons.place_outlined),
        suffixIcon: const Icon(Icons.search),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class SettlementPick {
  const SettlementPick(this.id);
  final int? id;
}

Future<SettlementPick?> showSettlementSearch(
  BuildContext context, {
  required List<dynamic> settlements,
  int? selectedId,
  bool allowAll = false,
  String allLabel = 'Все объявления',
}) {
  return showModalBottomSheet<SettlementPick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _SettlementSearchSheet(
        settlements: settlements,
        selectedId: selectedId,
        allowAll: allowAll,
        allLabel: allLabel,
      ),
    ),
  );
}

class _SettlementSearchSheet extends StatefulWidget {
  const _SettlementSearchSheet({
    required this.settlements,
    required this.selectedId,
    required this.allowAll,
    required this.allLabel,
  });

  final List<dynamic> settlements;
  final int? selectedId;
  final bool allowAll;
  final String allLabel;

  @override
  State<_SettlementSearchSheet> createState() => _SettlementSearchSheetState();
}

class _SettlementSearchSheetState extends State<_SettlementSearchSheet> {
  final query = TextEditingController();

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _rows {
    final q = query.text.trim().toLowerCase();
    final out = <Map<String, dynamic>>[];
    for (final s in widget.settlements) {
      if (s is! Map) continue;
      final name = '${s['display_name'] ?? ''}'.toLowerCase();
      if (q.isEmpty || name.contains(q)) {
        out.add(Map<String, dynamic>.from(s));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _rows;
    final available = MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom;
    final h = (available * 0.72).clamp(280.0, 640.0);
    return SizedBox(
      height: h,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(kPlaceLabel, style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: kPlaceTypeHint,
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(bottom: context.systemBottomInset),
              children: [
                if (widget.allowAll &&
                    (query.text.trim().isEmpty ||
                        widget.allLabel.toLowerCase().contains(query.text.trim().toLowerCase())))
                  ListTile(
                    leading: Icon(
                      widget.selectedId == null ? Icons.check_circle : Icons.public_outlined,
                      color: widget.selectedId == null ? scheme.primary : null,
                    ),
                    title: Text(widget.allLabel),
                    onTap: () => Navigator.pop(context, const SettlementPick(null)),
                  ),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      kPlaceNotInList,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                else
                  ...rows.map((s) {
                    final id = s['id'] as int;
                    final selected = widget.selectedId == id;
                    return ListTile(
                      leading: Icon(
                        selected ? Icons.check_circle : Icons.place_outlined,
                        color: selected ? scheme.primary : null,
                      ),
                      title: Text('${s['display_name']}'),
                      onTap: () => Navigator.pop(context, SettlementPick(id)),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
