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
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          n.summary,
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight:
                                                FontWeight.w600,
                                          ),
                                        ),
                                        if (n.body.isNotEmpty)
                                          Text(
                                            n.body,
                                            maxLines: 3,
                                            overflow: TextOverflow
                                                .ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        Text(
                                          n.appName,
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () =>
                                        c.dismissNotification(n.id),
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(
                                        Icons.close,
                                        size: 16,
                                      ),
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
      child: Padding(
        padding: const EdgeInsets.only(top: kCcTopOffset + 4),
        child: SizedBox(
          width: 380,
          child: OasisGlass(
            borderRadius: 14,
            blur: 40,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
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
        ),
      ),
    );
  }
}
