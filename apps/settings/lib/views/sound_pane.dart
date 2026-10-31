import 'dart:async';

import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../state/settings_state.dart';

class SoundPane extends StatefulWidget {
  const SoundPane({super.key, required this.state});

  final SettingsState state;

  @override
  State<SoundPane> createState() => _SoundPaneState();
}

class _SoundPaneState extends State<SoundPane> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.state.refreshAudio());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final state = widget.state;
    final b = state.backend;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsSound, style: text.titleLarge),
        const SizedBox(height: 16),
        OasisSection(
          children: [
            OasisRow(
              leading: const Icon(Icons.volume_up, size: 20),
              title: l10n.settingsVolume,
              trailing: SizedBox(
                width: 180,
                child: OasisSlider(
                  value: state.volume,
                  onChanged:
                      b == null ? null : (v) => state.volumeLevel = v,
                ),
              ),
            ),
          ],
        ),
        if (state.audioOutputs.isNotEmpty) ...[
          const SizedBox(height: 16),
          OasisSection(
            title: l10n.soundOutput,
            children: [
              for (final d in state.audioOutputs)
                _deviceRow(
                  context,
                  d,
                  Icons.speaker,
                  () => unawaited(state.selectAudioOutput(d.name)),
                ),
            ],
          ),
        ],
        if (state.audioInputs.isNotEmpty) ...[
          const SizedBox(height: 16),
          OasisSection(
            title: l10n.soundInput,
            children: [
              for (final d in state.audioInputs)
                _deviceRow(
                  context,
                  d,
                  Icons.mic,
                  () => unawaited(state.selectAudioInput(d.name)),
                ),
            ],
          ),
        ],
        if (state.audioCards.any((c) => c.profiles.isNotEmpty)) ...[
          const SizedBox(height: 16),
          OasisSection(
            title: l10n.soundProfiles,
            children: [
              for (final c in state.audioCards)
                if (c.profiles.isNotEmpty) _profileRow(context, c),
            ],
          ),
        ],
      ],
    );
  }

  Widget _deviceRow(
    BuildContext context,
    OasisAudioDevice d,
    IconData icon,
    VoidCallback onTap,
  ) {
    final p = OasisStyle.of(context).palette;
    return OasisRow(
      leading: Icon(icon, size: 20),
      title: d.description.isNotEmpty ? d.description : d.name,
      trailing: d.isDefault
          ? Icon(Icons.check, size: 16, color: p.accent)
          : const SizedBox.shrink(),
      onTap: onTap,
    );
  }

  Widget _profileRow(BuildContext context, OasisAudioCard c) {
    final state = widget.state;
    final active = c.profiles.any((p) => p.name == c.activeProfile)
        ? c.activeProfile
        : null;
    return OasisRow(
      leading: const Icon(Icons.settings_input_component, size: 20),
      title: c.description.isNotEmpty ? c.description : c.name,
      trailing: DropdownButton<String>(
        value: active,
        underline: const SizedBox.shrink(),
        items: [
          for (final p in c.profiles)
            DropdownMenuItem(
              value: p.name,
              child: Text(
                p.description.isNotEmpty ? p.description : p.name,
              ),
            ),
        ],
        onChanged: (v) {
          if (v != null) {
            unawaited(state.selectAudioProfile(c.name, v));
          }
        },
      ),
    );
  }
}
