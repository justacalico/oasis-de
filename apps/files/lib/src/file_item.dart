import 'package:flutter/painting.dart';

class FileItem {
  const FileItem({
    required this.path,
    required this.name,
    required this.isDir,
    this.size = 0,
    this.modified,
    this.thumb,
  });

  final String path;
  final String name;
  final bool isDir;
  final int size;
  final DateTime? modified;
  final ImageProvider? thumb;

  String get extension {
    final i = name.lastIndexOf('.');
    if (i <= 0 || i == name.length - 1) return '';
    return name.substring(i + 1).toLowerCase();
  }

  static const _imageExts = {
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'avif',
  };
  static const _audioExts = {
    'mp3', 'flac', 'ogg', 'wav', 'm4a', 'aac', 'opus',
  };
  static const _videoExts = {
    'mp4', 'mkv', 'webm', 'avi', 'mov', 'm4v',
  };
  static const _archiveExts = {
    'zip', 'tar', 'gz', 'bz2', 'xz', 'zst', '7z', 'rar',
  };
  static const _textExts = {
    'txt', 'md', 'dart', 'py', 'js', 'ts', 'json', 'yaml', 'yml',
    'toml', 'c', 'cc', 'cpp', 'h', 'rs', 'go', 'sh', 'xml', 'html',
    'css', 'log', 'csv', 'ini', 'conf',
  };

  bool get isImage => !isDir && _imageExts.contains(extension);
  bool get isAudio => !isDir && _audioExts.contains(extension);
  bool get isVideo => !isDir && _videoExts.contains(extension);
  bool get isArchive => !isDir && _archiveExts.contains(extension);
  bool get isText => !isDir && _textExts.contains(extension);
  bool get isPdf => !isDir && extension == 'pdf';
}

enum BookmarkKind {
  home,
  documents,
  downloads,
  pictures,
  music,
  videos,
  trash,
  mount,
  root,
}

class FileBookmark {
  const FileBookmark({
    required this.kind,
    required this.path,
    this.label = '',
  });

  final BookmarkKind kind;
  final String path;
  final String label;
}
