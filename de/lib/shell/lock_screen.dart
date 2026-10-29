import 'dart:ui';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import 'package:oasis_ui/oasis_ui.dart';

import 'shell_controller.dart';

class ShellLockScreen extends StatefulWidget {
  const ShellLockScreen({super.key, required this.controller});

  final ShellController controller;

  @override
  State<ShellLockScreen> createState() => _ShellLockScreenState();
}

class _ShellLockScreenState extends State<ShellLockScreen> {
  final _password = TextEditingController();
  var _wrong = false;
  var _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.controller.tryUnlock(_password.text);
    if (mounted) {
      setState(() {
        _busy = false;
        _wrong = !ok;
        if (ok) _password.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final style = OasisStyle.of(context);
    final p = style.palette;
    final text = Theme.of(context).textTheme;
    final now = clock.now();
    final hour = '${now.hour}'.padLeft(2, '0');
    final minute = '${now.minute}'.padLeft(2, '0');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: ColoredBox(
          color: p.windowBackground.withValues(alpha: 0.5),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 40,
                  color: p.textPrimary,
                ),
                const SizedBox(height: 16),
                Text(
                  '$hour:$minute',
                  style: text.displaySmall?.copyWith(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _password,
                    autofocus: true,
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: p.cardBackground.withValues(alpha: 0.6),
                      hintText: l10n.lockHint,
                      hintStyle: TextStyle(color: p.textTertiary),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(style.cardRadius),
                        borderSide: BorderSide(color: p.glassBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(style.cardRadius),
                        borderSide: BorderSide(color: p.glassBorder),
                      ),
                    ),
                    style: TextStyle(color: p.textPrimary),
                  ),
                ),
                if (_wrong) ...[
                  const SizedBox(height: 10),
                  Text(
                    l10n.lockWrong,
                    style: text.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 14),
                OasisButton(
                  label: l10n.lockUnlock,
                  variant: OasisButtonVariant.primary,
                  dense: true,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
