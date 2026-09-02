import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'state/app_state.dart';

const kPublicSite = 'https://legac.ru';

class AppUpdateInfo {
  AppUpdateInfo({
    required this.version,
    required this.build,
    required this.force,
    this.notes,
    required this.hasApk,
    this.downloadUrl,
  });

  final String version;
  final int build;
  final bool force;
  final String? notes;
  final bool hasApk;
  final String? downloadUrl;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      version: '${json['version'] ?? ''}',
      build: (json['build'] as num?)?.toInt() ?? 0,
      force: json['force'] == true,
      notes: json['notes'] as String?,
      hasApk: json['has_apk'] == true,
      downloadUrl: json['download_url'] as String?,
    );
  }
}

bool installedFromStore(String? installer) {
  final s = (installer ?? '').toLowerCase();
  if (s.isEmpty) return false;
  if (s.contains('packageinstaller') || s == 'com.android.shell') return false;
  const stores = [
    'com.android.vending',
    'ru.vk.store',
    'rustore',
    'com.huawei.appmarket',
    'com.amazon.venezia',
    'samsungapps',
    'com.xiaomi.mipicks',
    'com.oppo.market',
    'com.vivo.appstore',
  ];
  return stores.any(s.contains);
}

class UpdateService {
  UpdateService(this.api);

  final ApiClient api;

  static const _skipKey = 'update_skipped_build';

  Future<AppUpdateInfo?> fetch() async {
    try {
      final data = await api.request('/app/update') as Map<String, dynamic>;
      return AppUpdateInfo.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<bool> isUpdateAvailable(AppUpdateInfo remote) async {
    final info = await PackageInfo.fromPlatform();
    final local = int.tryParse(info.buildNumber) ?? 0;
    return remote.build > local;
  }

  Future<bool> fromStore() async {
    final info = await PackageInfo.fromPlatform();
    return installedFromStore(info.installerStore);
  }

  Future<bool> wasSkipped(int build) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_skipKey) == build;
  }

  Future<void> skip(int build) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_skipKey, build);
  }

  Future<void> clearSkip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_skipKey);
  }

  Future<void> openDownloadSite() async {
    final uri = Uri.parse(kPublicSite);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw ApiException('Не удалось открыть сайт');
    }
  }
}

/// Проверка при старте и по кнопке.
Future<bool> checkForAppUpdate(
  BuildContext context, {
  bool manual = false,
}) async {
  final api = context.read<AppState>().api;
  final service = UpdateService(api);
  if (await service.fromStore()) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Обновления приходят из магазина приложений')),
      );
    }
    return false;
  }
  final remote = await service.fetch();
  if (!context.mounted) return false;
  if (remote == null) {
    if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось проверить обновления')),
      );
    }
    return false;
  }
  final available = await service.isUpdateAvailable(remote);
  if (!available) {
    if (manual && context.mounted) {
      final info = await PackageInfo.fromPlatform();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('У вас актуальная версия ${info.version}+${info.buildNumber}')),
        );
      }
    }
    return false;
  }
  if (!manual && !remote.force && await service.wasSkipped(remote.build)) {
    return false;
  }
  if (!context.mounted) return false;
  await showDialog<void>(
    context: context,
    barrierDismissible: !remote.force,
    builder: (_) => _UpdateDialog(service: service, remote: remote),
  );
  return true;
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.service, required this.remote});

  final UpdateService service;
  final AppUpdateInfo remote;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool busy = false;
  String? error;

  Future<void> _openSite() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.service.clearSkip();
      await widget.service.openDownloadSite();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = AppState.userFriendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = widget.remote;
    return AlertDialog(
      title: Text(remote.force ? 'Нужно обновление' : 'Есть обновление'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Версия ${remote.version}'),
          const SizedBox(height: 8),
          Text(
            'Откроется сайт — скачайте файл и установите поверх текущего. Вход сохранится.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35, fontSize: 13),
          ),
          if (remote.notes != null && remote.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(remote.notes!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35)),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        if (!remote.force && !busy)
          TextButton(
            onPressed: () async {
              await widget.service.skip(remote.build);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Позже'),
          ),
        FilledButton(
          onPressed: busy ? null : _openSite,
          child: Text(busy ? 'Открываю…' : 'На сайт'),
        ),
      ],
    );
  }
}
