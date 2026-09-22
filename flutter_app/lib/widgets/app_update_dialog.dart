import 'package:flutter/material.dart';

import '../services/app_update_installer.dart';
import '../services/app_update_service.dart';

Future<void> showAppUpdateDialog(
  BuildContext context,
  AppUpdateInfo update,
  AppUpdateService service,
) async {
  var progress = 0.0;
  var downloading = false;
  var cancelled = false;
  String? error;
  var cancellationToken = UpdateCancellationToken();
  await showDialog<void>(
    context: context,
    barrierDismissible: !update.updateRequired && !downloading,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => PopScope(
        canPop: !update.updateRequired && !downloading,
        child: AlertDialog(
          title: Text(update.updateRequired ? '必须更新应用' : '发现新版本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('最新版本：${update.latestVersion}'),
              if (update.releaseNotes?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text(update.releaseNotes!),
              ],
              if (downloading) ...[
                const SizedBox(height: 18),
                LinearProgressIndicator(value: progress > 0 ? progress : null),
                const SizedBox(height: 8),
                Text(progress > 0
                    ? '正在下载 ${(progress * 100).toStringAsFixed(0)}%'
                    : '正在准备下载…'),
              ],
              if (cancelled) ...[
                const SizedBox(height: 12),
                const Text('下载已取消，可以继续使用当前版本。'),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            if (!update.updateRequired && !downloading)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('暂不更新'),
              ),
            if (downloading)
              TextButton(
                onPressed: () {
                  cancellationToken.cancel();
                  setState(() {
                    downloading = false;
                    cancelled = true;
                  });
                },
                child: const Text('取消下载'),
              ),
            if (!downloading)
              FilledButton(
                onPressed: update.downloadUrl?.isNotEmpty != true
                    ? null
                    : () async {
                        cancellationToken = UpdateCancellationToken();
                        setState(() {
                          downloading = true;
                          cancelled = false;
                          error = null;
                        });
                        try {
                          await downloadAndInstallUpdate(
                            downloadUrl: update.downloadUrl!,
                            expectedSha256: update.sha256,
                            cancellationToken: cancellationToken,
                            onProgress: (value) =>
                                setState(() => progress = value),
                          );
                        } on UpdateDownloadCancelled {
                          if (context.mounted) {
                            setState(() {
                              downloading = false;
                              cancelled = true;
                            });
                          }
                        } catch (exception) {
                          if (context.mounted) {
                            setState(() {
                              downloading = false;
                              error = exception.toString();
                            });
                          }
                        }
                      },
                child: Text(cancelled || error != null ? '重新下载' : '立即更新'),
              ),
          ],
        ),
      ),
    ),
  );
}
