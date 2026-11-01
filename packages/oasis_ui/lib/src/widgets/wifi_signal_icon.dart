import 'package:flutter/material.dart';

IconData wifiSignalIcon(int signal) => switch (signal) {
  >= 75 => Icons.signal_wifi_4_bar,
  >= 50 => Icons.network_wifi_3_bar,
  >= 25 => Icons.network_wifi_2_bar,
  _ => Icons.network_wifi_1_bar,
};
