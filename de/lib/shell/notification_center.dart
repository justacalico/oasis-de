import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'control_center.dart';
import 'shell_controller.dart';

class NotificationCenterPanel extends StatelessWidget {
  const NotificationCenterPanel({super.key, required this.controller});

  final ShellController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final c = controller;
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: kCcTopOffset, right: 10),
        child: SizedBox(
          width: 330,
          child: GestureDetector(
            onTap: () {},
            child: OasisGlass(
              borderRadius: 18,
              blur: 40,
              padding: const EdgeInsets.all(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            l10n.notifCenter,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: c.clearNotifications,
                          child: Text(l10n.notifClearAll),
                        ),
                      ],
                    ),
                    if (c.notifications.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text(
                            l10n.notifEmpty,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final n in c.notifications)
                              Padding(
                                key: ValueKey(n.id),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            n.summary,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (n.body.isNotEmpty)
                                            Text(
                                              n.body,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          Text(
                                            n.appName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                          if (n.actions.length > 1)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Wrap(
                                                spacing: 10,
                                                children: [
                                                  for (
                                                    var i = 0;
                                                    i + 1 < n.actions.length;
                                                    i += 2
                                                  )
                                                    if (n.actions[i] !=
                                                            'default' &&
                                                        n.actions[i] !=
                                                            'cancel')
                                                      GestureDetector(
                                                        onTap: () => c
                                                            .invokeNotificationAction(
                                                              n,
                                                              n.actions[i],
                                                            ),
                                                        child: Text(
                                                          n.actions[i + 1],
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color:
                                                                OasisStyle.of(
                                                                      context,
                                                                    )
                                                                    .palette
                                                                    .accent,
                                                          ),
                                                        ),
                                                      ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => c.dismissNotification(n.id),
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(Icons.close, size: 16),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NotificationBanner extends StatelessWidget {
  const NotificationBanner({super.key, required this.controller});

  final ShellController controller;

  @override
  Widget build(BuildContext context) {
    final n = controller.bannerNotification;
    if (n == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topCenter,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(n.id),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 250),
        builder: (context, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, -10 * (1 - v)),
            child: child,
          ),
        ),
        child: MouseRegion(
          onEnter: (_) => controller.pauseBannerDismiss(),
          onExit: (_) => controller.resumeBannerDismiss(),
          child: SizedBox(
            width: 380,
            child: GestureDetector(
              onTap: () {
                controller.dismissBanner();
                if (!controller.notificationCenterOpen) {
                  controller.toggleNotificationCenter();
                }
              },
              child: OasisGlass(
                borderRadius: 14,
                blur: 40,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (n.body.isNotEmpty)
                            Text(
                              n.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => controller.dismissNotification(n.id),
                      child: Semantics(
                        button: true,
                        label: OasisLocalizations.of(context).notifClearAll,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.close,
                            size: 15,
                            color: OasisStyle.of(context).palette.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
