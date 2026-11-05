import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'file_item.dart';

String fileBookmarkLabel(OasisLocalizations l10n, FileBookmark b) {
  return switch (b.kind) {
    BookmarkKind.home => l10n.filesBookmarkHome,
    BookmarkKind.documents => l10n.filesBookmarkDocuments,
    BookmarkKind.downloads => l10n.filesBookmarkDownloads,
    BookmarkKind.pictures => l10n.filesBookmarkPictures,
    BookmarkKind.music => l10n.filesBookmarkMusic,
    BookmarkKind.videos => l10n.filesBookmarkVideos,
    BookmarkKind.trash => l10n.filesBookmarkTrash,
    BookmarkKind.mount => b.label,
    BookmarkKind.root => l10n.filesBookmarkRoot,
  };
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = -1;
  do {
    v /= 1024;
    i++;
  } while (v >= 1024 && i < units.length - 1);
  return '${v.toStringAsFixed(v >= 10 ? 0 : 1)} ${units[i]}';
}

final _dateFormats = <String, DateFormat>{};

String formatFileDate(BuildContext context, DateTime? dt) {
  if (dt == null) return '';
  final locale = Localizations.localeOf(context).toString();
  final fmt = _dateFormats.putIfAbsent(
    locale,
    () => DateFormat.yMMMd(locale).add_Hm(),
  );
  return fmt.format(dt);
}

IconData fileIcon(FileItem item) {
  if (item.isDir) return Icons.folder;
  if (item.isImage) return Icons.image;
  if (item.isAudio) return Icons.music_note;
  if (item.isVideo) return Icons.movie;
  if (item.isArchive) return Icons.folder_zip;
  if (item.isPdf) return Icons.picture_as_pdf;
  return Icons.description;
}

class FileToolButton extends StatelessWidget {
  const FileToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return OasisTooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 17, color: p.textSecondary),
          ),
        ),
      ),
    );
  }
}

class FileBookmarkTile extends StatelessWidget {
  const FileBookmarkTile({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: active
                ? p.accent.withValues(alpha: 0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class FileListTile extends StatelessWidget {
  const FileListTile({
    super.key,
    required this.item,
    required this.selected,
  });

  final FileItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: selected
            ? p.accent.withValues(alpha: 0.25)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(fileIcon(item), size: 16, color: p.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.name,
              style: text.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              item.isDir ? '' : formatFileSize(item.size),
              style: text.bodySmall,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              formatFileDate(context, item.modified),
              style: text.bodySmall,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class FileGridTile extends StatelessWidget {
  const FileGridTile({super.key, required this.item, required this.selected});

  final FileItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: selected
            ? p.accent.withValues(alpha: 0.25)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (item.isImage)
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image(
                  image: item.thumb ??
                      ResizeImage(
                        FileImage(File(item.path)),
                        width: 220,
                      ),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stack) =>
                      Icon(fileIcon(item), size: 34, color: p.accent),
                ),
              ),
            )
          else
            Expanded(
              child: Center(
                child: Icon(fileIcon(item), size: 34, color: p.accent),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            item.name,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
