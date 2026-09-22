import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../core/design_system.dart';
import '../../services/minecraft_query.dart';
import '../../services/minecraft_server_service.dart';
import '../../services/local_image_store.dart';
import '../../widgets/local_or_network_image.dart';

/// 我的世界服务器详情与设置。
class MinecraftServerPage extends StatefulWidget {
  const MinecraftServerPage({super.key});

  @override
  State<MinecraftServerPage> createState() => _MinecraftServerPageState();
}

class _MinecraftServerPageState extends State<MinecraftServerPage> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _portController = TextEditingController();
  final _noteController = TextEditingController();
  final _coverController = TextEditingController();
  MinecraftEdition _edition = MinecraftEdition.java;
  bool _useAutomaticIcon = true;
  bool _uploadingCover = false;
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final server = context.read<MinecraftServerService>().server;
    _nameController.text = server.name;
    _addressController.text = server.address;
    _portController.text = server.port.toString();
    _noteController.text = server.note;
    _coverController.text = server.customCoverUrl ?? '';
    _edition = server.edition;
    _useAutomaticIcon = server.useAutomaticIcon;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _portController.dispose();
    _noteController.dispose();
    _coverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<MinecraftServerService>();
    final scheme = Theme.of(context).colorScheme;
    final refreshLabel =
        service.loading ? '正在查询…' : service.error ?? '每30秒自动刷新，点击右上角可手动查询';
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的世界服务器',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              onPressed: service.loading ? null : service.refreshStatus,
              icon: Icon(Icons.refresh_rounded, color: scheme.primary))
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _serverOverview(context, service.server),
          const SizedBox(height: AppSpacing.xl),
          Text('服务器设置',
              style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(children: [
              TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                      labelText: '服务器名称',
                      hintText: '例如：我的生存服务器',
                      prefixIcon: Icon(Icons.title_rounded))),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                      labelText: '服务器地址', prefixIcon: Icon(Icons.dns_rounded))),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '端口',
                      prefixIcon: Icon(Icons.settings_ethernet_rounded))),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<MinecraftEdition>(
                segments: const [
                  ButtonSegment(
                      value: MinecraftEdition.java, label: Text('Java版')),
                  ButtonSegment(
                      value: MinecraftEdition.bedrock, label: Text('基岩版'))
                ],
                selected: {_edition},
                onSelectionChanged: (values) =>
                    setState(() => _edition = values.first),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: '本地备注',
                      hintText: '例如：和朋友一起玩的生存服',
                      prefixIcon: Icon(Icons.notes_rounded))),
              const SizedBox(height: AppSpacing.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.image_outlined),
                title: const Text('自定义封面图片'),
                subtitle: Text(_uploadingCover
                    ? '正在保存图片…'
                    : (_coverController.text.isEmpty
                        ? '从相册选择图片保存到本机'
                        : '图片已保存到本机')),
                trailing: FilledButton.tonalIcon(
                  onPressed: _uploadingCover ? null : _pickAndUploadCover,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('选择相册'),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('使用自动获取的服务器图标'),
                subtitle: const Text('没有自定义封面时优先使用 Java 版服务器图标'),
                value: _useAutomaticIcon,
                onChanged: (value) => setState(() => _useAutomaticIcon = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                  width: double.infinity,
                  child: AppAccentButton(
                      label: '保存并查询',
                      icon: Icons.save_outlined,
                      onPressed: _saveServer)),
            ]),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(refreshLabel,
              style: TextStyle(
                  color: service.error == null
                      ? scheme.primary.withValues(alpha: .7)
                      : scheme.primary,
                  fontSize: 12)),
        ],
      ),
    );
  }

  Widget _serverOverview(BuildContext context, MinecraftServer server) {
    final scheme = Theme.of(context).colorScheme;
    final cover = server.customCoverUrl?.isNotEmpty == true
        ? server.customCoverUrl
        : (server.useAutomaticIcon ? server.favicon : null);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _serverCoverThumbnail(context, cover),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  server.address.isEmpty ? '尚未绑定服务器' : server.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.primary.withValues(alpha: .84),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _statusBadge(context, server.online),
        ]),
        if (server.motd.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            server.motd,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: .88),
              fontSize: 16,
              height: 1.35,
            ),
          ),
        ],
        if (server.note.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '备注：${server.note}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: .78),
              fontSize: 16,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(children: [
          _stat(context, Icons.people_alt_outlined,
              '${server.onlinePlayers}/${server.maxPlayers}', '在线人数'),
          _stat(context, Icons.code_rounded, server.version, '游戏版本'),
          _stat(context, Icons.lan_outlined, '${server.port}', '端口'),
        ]),
      ]),
    );
  }

  Widget _serverCoverThumbnail(BuildContext context, String? source) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        width: 72,
        height: 72,
        child: source?.isNotEmpty == true
            ? localOrNetworkImage(source!, fit: BoxFit.cover)
            : _defaultCover(context),
      ),
    );
  }

  Widget _defaultCover(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.primary),
      child: Center(
          child: Icon(Icons.public_rounded, color: scheme.onPrimary, size: 48)),
    );
  }

  Widget _statusBadge(BuildContext context, bool online) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Text(online ? '在线' : '离线',
            style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 12)));
  }

  Widget _stat(
      BuildContext context, IconData icon, String value, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
        child: Column(children: [
      Icon(icon, color: scheme.primary),
      const SizedBox(height: 6),
      Text(value,
          style:
              TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w800)),
      const SizedBox(height: 3),
      Text(label,
          style: TextStyle(
              color: scheme.onSurface.withValues(alpha: .72), fontSize: 11))
    ]));
  }

  Future<bool> _requestGalleryPermission() async {
    if (kIsWeb) return true;
    final status = await Permission.photos.request();
    if (status.isGranted || status.isLimited) return true;
    if (!mounted) return false;
    final openSettings = status.isPermanentlyDenied
        ? await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('需要相册权限'),
                content: const Text('请在系统设置中允许“小酒馆”访问照片，才能选择自定义封面。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('去设置')),
                ],
              ),
            ) ??
            false
        : false;
    if (openSettings) await openAppSettings();
    return false;
  }

  Future<void> _pickAndUploadCover() async {
    if (!await _requestGalleryPermission()) return;
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;

    setState(() => _uploadingCover = true);
    try {
      final path = await saveLocalImage(image);
      if (path == null || path.isEmpty) throw StateError('图片保存失败');
      if (!mounted) return;
      setState(() => _coverController.text = path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片已保存到本机')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片保存失败，请检查应用存储权限')),
      );
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _saveServer() async {
    final port = int.tryParse(_portController.text.trim());
    if (_nameController.text.trim().isEmpty ||
        _addressController.text.trim().isEmpty ||
        port == null) {
      return;
    }
    await context.read<MinecraftServerService>().updateServer(
        name: _nameController.text.trim(),
        address: _addressController.text.trim(),
        port: port,
        edition: _edition,
        note: _noteController.text.trim(),
        customCoverUrl: _coverController.text.trim().isEmpty
            ? null
            : _coverController.text.trim(),
        useAutomaticIcon: _useAutomaticIcon);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('服务器设置已保存，正在查询状态')));
  }
}
