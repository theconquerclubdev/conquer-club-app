import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../providers/master_data_provider.dart';

// ============================================================
// BODY TRANSFORMATION — before/after progress photos
// ============================================================

const _bucket = 'progress-photos';
const _table = 'member_progress_photos';

const _signedUrlTtl = Duration(days: 30);
const _signedUrlRefreshThreshold = Duration(days: 3);

enum _Slot { beforeFront, beforeBack, afterFront, afterBack }

extension on _Slot {
  bool get isBefore => this == _Slot.beforeFront || this == _Slot.beforeBack;
  bool get isFront => this == _Slot.beforeFront || this == _Slot.afterFront;

  String get storageFileName {
    switch (this) {
      case _Slot.beforeFront:
        return 'before_front.webp';
      case _Slot.beforeBack:
        return 'before_back.webp';
      case _Slot.afterFront:
        return 'after_front.webp';
      case _Slot.afterBack:
        return 'after_back.webp';
    }
  }

  String get col {
    switch (this) {
      case _Slot.beforeFront:
        return 'before_front';
      case _Slot.beforeBack:
        return 'before_back';
      case _Slot.afterFront:
        return 'after_front';
      case _Slot.afterBack:
        return 'after_back';
    }
  }

  String get label {
    switch (this) {
      case _Slot.beforeFront:
        return 'Before · Front';
      case _Slot.beforeBack:
        return 'Before · Back';
      case _Slot.afterFront:
        return 'After · Front';
      case _Slot.afterBack:
        return 'After · Back';
    }
  }
}

class MemberProgressScreen extends StatefulWidget {
  final String? memberId; // ✅ ADDED: If provided, shows this member's photos
  final bool readOnly; // ✅ ADDED: When true, disables all uploads (coach view)

  const MemberProgressScreen({
    super.key,
    this.memberId,
    this.readOnly = false,
  });

  @override
  State<MemberProgressScreen> createState() => _MemberProgressScreenState();
}

class _MemberProgressScreenState extends State<MemberProgressScreen> {
  bool _loading = true;
  final Set<_Slot> _uploading = {};

  final Map<_Slot, String?> _path = {for (final s in _Slot.values) s: null};
  final Map<_Slot, String?> _url = {for (final s in _Slot.values) s: null};
  final Map<_Slot, DateTime?> _urlExpiresAt = {
    for (final s in _Slot.values) s: null,
  };
  final Map<_Slot, int> _version = {for (final s in _Slot.values) s: 0};
  final Map<_Slot, DateTime?> _updatedAt = {
    for (final s in _Slot.values) s: null,
  };

  // ✅ UPDATED: Uses widget.memberId if provided, otherwise logged-in user
  String get _memberId {
    if (widget.memberId != null) return widget.memberId!;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }
    return user.id;
  }

  bool get _isSunday => DateTime.now().weekday == DateTime.sunday;

  bool _isLoadingPhotos = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // ✅ Guard against overlapping calls
    if (_isLoadingPhotos) return;
    _isLoadingPhotos = true;

    setState(() => _loading = true);
    try {
      final row = await Supabase.instance.client
          .from(_table)
          .select()
          .eq('member_id', _memberId)
          .maybeSingle();

      if (row != null) {
        for (final slot in _Slot.values) {
          _path[slot] = row['${slot.col}_path'] as String?;
          _url[slot] = row['${slot.col}_url'] as String?;
          final exp = row['${slot.col}_url_expiry'] as String?;
          _urlExpiresAt[slot] = exp == null ? null : DateTime.tryParse(exp);
          final updated = row['${slot.col}_updated_at'] as String?;
          _updatedAt[slot] =
              updated == null ? null : DateTime.tryParse(updated);
        }
      }

      final refreshed = <String, dynamic>{};
      for (final slot in _Slot.values) {
        final path = _path[slot];
        if (path == null) continue;
        final expires = _urlExpiresAt[slot];
        final needsRefresh = _url[slot] == null ||
            expires == null ||
            expires.isBefore(DateTime.now().add(_signedUrlRefreshThreshold));
        if (!needsRefresh) continue;

        final signed = await Supabase.instance.client.storage
            .from(_bucket)
            .createSignedUrl(path, _signedUrlTtl.inSeconds);
        final newExpiry = DateTime.now().add(_signedUrlTtl);
        _url[slot] = signed;
        _urlExpiresAt[slot] = newExpiry;
        refreshed['${slot.col}_url'] = signed;
        refreshed['${slot.col}_url_expiry'] = newExpiry.toIso8601String();
      }

      if (refreshed.isNotEmpty) {
        await Supabase.instance.client.from(_table).upsert({
          'member_id': _memberId,
          ...refreshed,
        });
      }
    } catch (e) {
      print('Error loading progress photos: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
      _isLoadingPhotos = false;
    }
  }

  bool _canUpload(_Slot slot) {
    final hasExisting = _path[slot] != null;
    if (slot.isBefore) {
      if (!hasExisting) return true;
      final uploadedAt = _updatedAt[slot];
      if (uploadedAt == null)
        return false; // no timestamp on record: play safe, treat as locked
      return _isSameDay(uploadedAt, DateTime.now());
    }
    if (!hasExisting) return true;
    return _isSunday;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String? _blockedReason(_Slot slot) {
    if (_canUpload(slot)) return null;
    if (slot.isBefore)
      return 'Before photos can only be replaced on the day you first uploaded them.';
    return 'After photos can only be updated on Sundays.';
  }

  Future<void> _handleTap(_Slot slot) async {
    if (widget.readOnly) return;
    final blocked = _blockedReason(slot);
    if (blocked != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }
    final source = await _pickSource();
    if (source == null) return;
    await _pickCompressAndUpload(slot, source);
  }

  Future<ImageSource?> _pickSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.gold),
              title:
                  const Text('Camera', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.gold),
              title:
                  const Text('Gallery', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List> _compressImageWeb(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final image = await decodeImageFromList(bytes);

      int originalWidth = image.width;
      int originalHeight = image.height;

      int newWidth = originalWidth;
      int newHeight = originalHeight;

      if (newWidth > 1080) {
        newWidth = 1080;
        newHeight = (originalHeight * 1080 / originalWidth).round();
      }
      if (newHeight > 1350) {
        newHeight = 1350;
        newWidth = (originalWidth * 1350 / originalHeight).round();
      }

      // Use FlutterImageCompress for web as well
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        format: CompressFormat.webp,
        quality: 65,
        minWidth: newWidth,
        minHeight: newHeight,
        keepExif: false,
      );

      return compressed ?? bytes;
    } catch (e) {
      print('Web compression error: $e');
      rethrow;
    }
  }

  Future<void> _pickCompressAndUpload(_Slot slot, ImageSource source) async {
    final picker = ImagePicker();
    XFile? picked;

    try {
      // Web doesn't support preferredCameraDevice
      if (kIsWeb) {
        picked = await picker.pickImage(
          source: source,
          maxWidth: 1080,
          maxHeight: 1350,
        );
      } else {
        picked = await picker.pickImage(
          source: source,
          maxWidth: 1080,
          maxHeight: 1350,
          imageQuality: 65,
          preferredCameraDevice: CameraDevice.rear,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
      return;
    }

    if (picked == null) return;

    setState(() => _uploading.add(slot));
    try {
      Uint8List bytes;
      String contentType;

      if (kIsWeb) {
        bytes = await _compressImageWeb(picked);
        contentType = 'image/webp';
      } else {
        final compressed = await _compressToWebp(picked.path);
        if (compressed == null) {
          throw Exception('Could not process that image.');
        }
        bytes = compressed;
        contentType = 'image/webp';
      }

      final path = '$_memberId/${slot.storageFileName}';

      await Supabase.instance.client.storage
          .from(_bucket)
          .uploadBinary(path, bytes,
              fileOptions: FileOptions(
                upsert: true,
                contentType: contentType,
              ));

      final signed = await Supabase.instance.client.storage
          .from(_bucket)
          .createSignedUrl(path, _signedUrlTtl.inSeconds);
      final expiry = DateTime.now().add(_signedUrlTtl);

      await Supabase.instance.client.from(_table).upsert({
        'member_id': _memberId,
        '${slot.col}_path': path,
        '${slot.col}_url': signed,
        '${slot.col}_url_expiry': expiry.toUtc().toIso8601String(),
        '${slot.col}_updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (!mounted) return;
      setState(() {
        _path[slot] = path;
        _url[slot] = signed;
        _urlExpiresAt[slot] = expiry;
        _updatedAt[slot] = DateTime.now();
        _version[slot] = _version[slot]! + 1;
      });

      if (mounted) {
        // Invalidate cache for the member
        MasterDataProvider.instance.invalidateCache(_memberId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${slot.label} uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading.remove(slot));
    }
  }

  String _cacheKey(_Slot slot) {
    final base = '${_memberId}_${slot.col}';
    return slot.isBefore ? base : '${base}_v${_version[slot]}';
  }

  Future<Uint8List?> _compressToWebp(String sourcePath) async {
    try {
      final result = await FlutterImageCompress.compressWithFile(
        sourcePath,
        format: CompressFormat.webp,
        quality: 65,
        minWidth: 1080,
        minHeight: 1350,
        keepExif: false,
      );
      return result;
    } catch (e) {
      print('Compression error: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          widget.readOnly
              ? 'Body Transformation (View Only)'
              : 'Body Transformation',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.gold,
              backgroundColor: AppColors.cardDark,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionHeader('Before', locked: true),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _photoCard(_Slot.beforeFront)),
                      const SizedBox(width: 12),
                      Expanded(child: _photoCard(_Slot.beforeBack)),
                    ],
                  ),
                  const SizedBox(height: 26),
                  _sectionHeader('After', locked: false),
                  const SizedBox(height: 4),
                  Text(
                    widget.readOnly
                        ? 'Viewing only — uploads happen from the member\'s app.'
                        : (_isSunday
                            ? 'It\'s Sunday — you can update your after photos today.'
                            : 'After photos can only be replaced on Sundays.'),
                    style: TextStyle(
                      color: widget.readOnly
                          ? Colors.grey
                          : (_isSunday ? AppColors.gold : Colors.grey),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _photoCard(_Slot.afterFront)),
                      const SizedBox(width: 12),
                      Expanded(child: _photoCard(_Slot.afterBack)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildInfoCard(),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String title, {required bool locked}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (locked) ...[
          const SizedBox(width: 6),
          const Icon(Icons.lock_outline, color: Colors.grey, size: 15),
        ],
      ],
    );
  }

  Widget _photoCard(_Slot slot) {
    final hasPhoto = _path[slot] != null;
    final isUploading = _uploading.contains(slot);
    final locked = slot.isBefore && hasPhoto && !_canUpload(slot);

    return GestureDetector(
      onTap: (isUploading || widget.readOnly) ? null : () => _handleTap(slot),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasPhoto && _url[slot] != null)
                CachedNetworkImage(
                  imageUrl: _url[slot]!,
                  cacheKey: _cacheKey(slot),
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.gold,
                      strokeWidth: 2,
                    ),
                  ),
                  errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.grey,
                  ),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        slot.isFront
                            ? Icons.accessibility_new
                            : Icons.accessibility_new_outlined,
                        color: Colors.grey.shade600,
                        size: 30,
                      ),
                      const SizedBox(height: 8),
                      if (widget.readOnly)
                        Text(
                          'No photo yet',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 10,
                          ),
                        )
                      else ...[
                        Icon(Icons.add_a_photo_outlined,
                            color: AppColors.gold.withOpacity(0.8), size: 20),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to upload',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              Positioned(
                left: 8,
                bottom: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    slot.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (locked && !widget.readOnly)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(Icons.lock, color: Colors.white70, size: 18),
                ),
              if (isUploading)
                Container(
                  color: Colors.black.withOpacity(0.55),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.gold),
                        SizedBox(height: 8),
                        Text(
                          'Compressing...',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    if (widget.readOnly) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Icon(Icons.visibility_outlined,
                color: Colors.grey.shade500, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'You\'re viewing this member\'s photos in read-only mode. '
                'Only the member can upload or replace their own photos.',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📸 HOW IT WORKS',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          _infoRow('🔒', 'Before photos', 'Replaceable same day, then locked'),
          const SizedBox(height: 4),
          _infoRow('📅', 'After photos', 'Update only on Sundays'),
          const SizedBox(height: 4),
          _infoRow('⚡', 'WebP format', 'Compressed for fast loading'),
          const SizedBox(height: 4),
          _infoRow('💾', 'Storage', 'One member = 4 photos max'),
        ],
      ),
    );
  }

  Widget _infoRow(String icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
