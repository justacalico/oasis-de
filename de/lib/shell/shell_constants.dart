import 'package:oasis_ui/oasis_ui.dart';

const kTopBarHeight = 30.0;
const kCcTopOffset = 34.0;
const kDashIconSize = 52.0;
const kDashHeight = kDashIconSize + 24.0;
const kMinWindowWidth = 360.0;
const kMinWindowHeight = 300.0;
const kDefaultWindowWidth = 480.0;
const kDefaultWindowHeight = 360.0;

const kWindowSpawnX = 56.0;
const kWindowSpawnY = 52.0;
const kWindowCascadeX = 28.0;
const kWindowCascadeY = 24.0;
const kWindowEdgeTop = kTopBarHeight + 4;
const kWindowEdgeMargin = 64.0;
const kWindowBottomMargin = 24.0;
const kSnapEdgeWidth = 8.0;
const kSnapBottomMargin = 8.0;

const kDefaultBrightness = 0.8;
const kDefaultVolume = 0.6;

const kLaunchTimeout = Duration(seconds: 8);
const kIdentifyDuration = Duration(seconds: 3);

/// Time the snip overlay stays hidden before the framebuffer is read,
/// so the overlay itself never lands in the capture.
const kScreenshotSettle = Duration(milliseconds: 150);
const kBannerTimeout = Duration(seconds: 5);
const kUnlockBackoffStep = Duration(milliseconds: 500);
const kMaxNotifications = 50;

/// Screen space the dash reserves for [OasisDashMode.push]. Other modes let
/// windows use the whole edge.
double dashReservedExtent(OasisDashSettings dash) {
  if (dash.mode != OasisDashMode.push) return 0;
  return dash.iconSize + 24.0;
}
