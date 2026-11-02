import 'package:oasis_ui/oasis_ui.dart';

const kMenuBarHeight = 30.0;
const kCcTopOffset = 34.0;
const kDockIconSize = 52.0;
const kDockHeight = kDockIconSize + 37.0;
const kMinWindowWidth = 360.0;
const kMinWindowHeight = 300.0;

/// Screen space the dock reserves for [OasisDockMode.push]. Other modes let
/// windows use the whole edge.
double dockReservedExtent(OasisDockSettings dock) {
  if (dock.mode != OasisDockMode.push) return 0;
  return dock.iconSize + 37.0;
}
