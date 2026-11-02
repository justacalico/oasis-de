import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class OasisAppIcon extends StatelessWidget {
  const OasisAppIcon({
    super.key,
    required this.icon,
    required this.colors,
    this.size = 48,
    this.iconPath,
    this.image,
  });

  final IconData icon;
  final List<Color> colors;
  final double size;
  final String? iconPath;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
        border: Border.all(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.25),
            width: size * 0.02),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.25),
            blurRadius: size * 0.12,
            offset: Offset(0, size * 0.04),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: size * 0.04,
            left: size * 0.12,
            right: size * 0.12,
            height: size * 0.42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFFFFFFF).withValues(alpha: 0.38),
                    const Color(0xFFFFFFFF).withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ),
          if (!kIsWeb && iconPath != null)
            Padding(
              padding: EdgeInsets.all(size * 0.12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(size * 0.16),
                child: iconPath!.endsWith('.svg')
                    ? _SvgFileIcon(
                        key: ValueKey(iconPath),
                        path: iconPath!,
                        icon: icon,
                        size: size,
                      )
                    : Image(
                        image: image ?? FileImage(File(iconPath!)),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) => Icon(
                          icon,
                          size: size * 0.55,
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
              ),
            )
          else
            Icon(icon,
                size: size * 0.55, color: const Color(0xFFFFFFFF)),
        ],
      ),
    );
  }
}

/// Reads an svg off disk asynchronously. `SvgPicture.file` can't be used
/// here: its `File` type isn't `dart:io`'s on the web, so it doesn't
/// compile for that target even though this branch is desktop-only.
class _SvgFileIcon extends StatefulWidget {
  const _SvgFileIcon({
    super.key,
    required this.path,
    required this.icon,
    required this.size,
  });

  final String path;
  final IconData icon;
  final double size;

  @override
  State<_SvgFileIcon> createState() => _SvgFileIconState();
}

class _SvgFileIconState extends State<_SvgFileIcon> {
  late final Future<Uint8List> _bytes = File(widget.path).readAsBytes();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return Icon(
            widget.icon,
            size: widget.size * 0.55,
            color: const Color(0xFFFFFFFF),
          );
        }
        return SvgPicture.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => Icon(
            widget.icon,
            size: widget.size * 0.55,
            color: const Color(0xFFFFFFFF),
          ),
        );
      },
    );
  }
}
