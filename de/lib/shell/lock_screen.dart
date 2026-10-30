import 'dart:async';
import 'dart:ui';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  late DateTime _now;
  Timer? _clockTimer;
  var _wrong = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _now = clock.now();
    _scheduleTick();
  }

  void _scheduleTick() {
    final next = DateTime(
      _now.year,
      _now.month,
      _now.day,
      _now.hour,
      _now.minute + 1,
    );
    _clockTimer = Timer(next.difference(_now), _tick);
  }

  void _tick() {
    if (mounted) {
      setState(() => _now = clock.now());
      _scheduleTick();
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
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
    final now = _now;
    final locale = Localizations.localeOf(context).toString();
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
                const SizedBox(height: 4),
                Text(
                  DateFormat.MEd(locale).format(now),
                  style: text.bodyMedium?.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 260,
                  child: OasisTextField(
                    controller: _password,
                    autofocus: true,
                    obscureText: true,
                    filled: true,
                    hintText: l10n.lockHint,
                    onSubmitted: (_) => _submit(),
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
