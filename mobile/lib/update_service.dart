import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'state/app_state.dart';

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

  Uri apkUri(AppUpdateInfo remote) {
    final raw = remote.downloadUrl ?? '/app/apk';
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return Uri.parse(raw);
    }
    final base = Uri.parse(api.baseUrl);
    // download_url from API is `/api/app/apk`; baseUrl is `…/api`
    if (raw.startsWith('/api/')) {
      final root = api.baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
      return Uri.parse('$root$raw');
    }
    final path = raw.startsWith('/') ? raw : '/$raw';
    final joined = base.path.endsWith('/') ? '${base.path}${path.substring(1)}' : '${base.path}$path';
    return base.replace(path: joined);
  }

  Future<File> downloadApk(
    AppUpdateInfo remote, {
    void Function(double progress)? onProgress,
  }) async {
    final uri = apkUri(remote);
    final client = http.Client();
    try {
      final req = http.Request('GET', uri);
      final res = await client.send(req);
      if (res.statusCode != 200) {
        throw ApiException('Не удалось скачать обновление (${res.statusCode})', statusCode: res.statusCode);
      }
      final total = res.contentLength ?? 0;
      var received = 0;
      final dir = await getTemporaryDirectory();
      // Один и тот же файл обновления — меньше шансов, что установщик
      // предложит «второе» приложение рядом со старым.
      final file = File('${dir.path}/ryadom56-update.apk');
      if (await file.exists()) {
        await file.delete();
      }
      // подчистить старые копии
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains('ryadom56') && entity.path.endsWith('.apk')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
      final sink = file.openWrite();
      await for (final chunk in res.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.close();
      return file;
    } finally {
      client.close();
    }
  }

  Future<void> installApk(File file) async {
    final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) {
      throw Exception(result.message.isNotEmpty ? result.message : 'Не удалось открыть установщик');
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
  bool downloading = false;
  double progress = 0;
  String? error;

  Future<void> _start() async {
    if (!widget.remote.hasApk) {
      setState(() => error = 'Файл обновления ещё не загружен на сервер. Попробуйте позже.');
      return;
    }
    setState(() {
      downloading = true;
      progress = 0;
      error = null;
    });
    try {
      final file = await widget.service.downloadApk(
        widget.remote,
        onProgress: (p) {
          if (mounted) setState(() => progress = p);
        },
      );
      await widget.service.clearSkip();
      if (!mounted) return;
      await widget.service.installApk(file);
      if (!mounted) return;
      Navigator.pop(context);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Установите обновление'),
          content: const Text(
            'Откроется установщик Android — подтвердите установку поверх текущей версии.\n\n'
            'Это заменит то же приложение «Рядом56», новый значок не появится.\n\n'
            'Если вдруг останутся два значка — удалите старый '
            '(тот, который не открывается или со старым номером версии).',
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          downloading = false;
          error = AppState.userFriendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = widget.remote;
    return AlertDialog(
      title: Text(remote.force ? 'Требуется обновление' : 'Доступно обновление'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Версия ${remote.version} (сборка ${remote.build})'),
          const SizedBox(height: 8),
          Text(
            'Обновление ставится поверх текущего приложения — данные и вход сохраняются.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35, fontSize: 13),
          ),
          if (remote.notes != null && remote.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(remote.notes!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35)),
          ],
          if (downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progress > 0 ? progress : null),
            const SizedBox(height: 8),
            Text(progress > 0 ? 'Скачивание ${(progress * 100).round()}%' : 'Скачивание…'),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        if (!remote.force && !downloading)
          TextButton(
            onPressed: () async {
              await widget.service.skip(remote.build);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Позже'),
          ),
        FilledButton(
          onPressed: downloading ? null : _start,
          child: Text(downloading ? 'Ждите…' : 'Обновить'),
        ),
      ],
    );
  }
}
