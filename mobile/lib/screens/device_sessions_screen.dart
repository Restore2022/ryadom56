import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../time_format.dart';
import '../ui_helpers.dart';

class DeviceSessionsScreen extends StatefulWidget {
  const DeviceSessionsScreen({super.key});

  @override
  State<DeviceSessionsScreen> createState() => _DeviceSessionsScreenState();
}

class _DeviceSessionsScreenState extends State<DeviceSessionsScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await context.read<AppState>().loadDeviceSessions();
      if (!mounted) return;
      setState(() {
        items = rows;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = AppState.userFriendlyError(e);
        loading = false;
      });
    }
  }

  String _title(Map<String, dynamic> row) {
    final brand = (row['device_brand'] as String?)?.trim() ?? '';
    final model = (row['device_model'] as String?)?.trim() ?? '';
    final name = [brand, model].where((e) => e.isNotEmpty).join(' ');
    return name.isEmpty ? 'Неизвестное устройство' : name;
  }

  String _when(Map<String, dynamic> row) {
    return formatApiDateTime((row['last_seen_at'] ?? row['created_at'])?.toString(), sep: ' ');
  }

  Future<void> _revokeAll({required bool othersOnly}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(othersOnly ? 'Выйти на других телефонах?' : 'Выйти на всех телефонах?'),
        content: Text(
          othersOnly
              ? 'На этом телефоне вы останетесь в аккаунте. На остальных потребуется вход.'
              : 'Потребуется снова войти по email и паролю, в том числе на этом телефоне.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      if (othersOnly) {
        await context.read<AppState>().revokeOtherSessions();
        if (!mounted) return;
        showAppSnack(context, 'Выполнен выход на других устройствах');
        await _load();
      } else {
        await context.read<AppState>().revokeAllSessions();
        if (!mounted) return;
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, AppState.userFriendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _revokeOne(Map<String, dynamic> row) async {
    final id = row['id'] as int?;
    if (id == null) return;
    final current = row['is_current'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(current ? 'Выйти на этом телефоне?' : 'Отключить устройство?'),
        content: Text(current ? 'Понадобится войти заново.' : 'На этом устройстве потребуется новый вход.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отключить')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await context.read<AppState>().revokeSession(id, isCurrent: current);
      if (!mounted) return;
      if (current) {
        Navigator.pop(context);
      } else {
        showAppSnack(context, 'Устройство отключено');
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, AppState.userFriendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Сессии устройств')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? errorState(context: context, message: error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Здесь телефоны, с которых выполнен вход. Можно выйти на всех сразу.',
                      style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: busy ? null : () => _revokeAll(othersOnly: false),
                      icon: const Icon(Icons.phonelink_erase_outlined),
                      label: const Text('Выйти на всех телефонах'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: busy ? null : () => _revokeAll(othersOnly: true),
                      child: const Text('Выйти на других устройствах'),
                    ),
                    const SizedBox(height: 20),
                    if (items.isEmpty)
                      emptyState(
                        context: context,
                        title: 'Пока одно устройство',
                        subtitle: 'После входа с другого телефона оно появится в списке.',
                        icon: Icons.smartphone_outlined,
                      )
                    else
                      ...items.map((row) {
                        final current = row['is_current'] == true;
                        final os = (row['device_os'] as String?)?.trim();
                        final ip = (row['last_ip'] as String?)?.trim();
                        final app = (row['app_version'] as String?)?.trim();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: Icon(current ? Icons.phone_android : Icons.devices_other),
                            title: Text(_title(row)),
                            subtitle: Text(
                              [
                                if (current) 'Этот телефон',
                                if (os != null && os.isNotEmpty) os,
                                if (app != null && app.isNotEmpty) 'приложение $app',
                                if (ip != null && ip.isNotEmpty) 'IP $ip',
                                _when(row),
                              ].where((e) => e.isNotEmpty).join('\n'),
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              tooltip: current ? 'Выйти здесь' : 'Отключить',
                              onPressed: busy ? null : () => _revokeOne(row),
                              icon: const Icon(Icons.logout),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }
}
