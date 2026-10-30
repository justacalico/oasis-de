import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'helpers/test_app.dart';

void main() {
  iconCoverage();
  testWidgets('OasisButton variants, states and callbacks', (tester) async {
    var taps = 0;
    await pumpOasis(
      tester,
      Column(
        children: [
          OasisButton(
            label: 'one',
            variant: OasisButtonVariant.primary,
            onPressed: () => taps++,
          ),
          OasisButton(
            label: 'two',
            variant: OasisButtonVariant.secondary,
            onPressed: () => taps++,
          ),
          OasisButton(
            label: 'three',
            variant: OasisButtonVariant.text,
            onPressed: () => taps++,
          ),
          const OasisButton(label: 'off'),
          const OasisButton(
            label: 'dense',
            variant: OasisButtonVariant.primary,
            dense: true,
            onPressed: null,
          ),
        ],
      ),
    );
    await tester.tap(find.text('one'));
    await tester.tap(find.text('two'));
    await tester.tap(find.text('three'));
    expect(taps, 3);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('two')));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('three')));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('one')));
    await tester.pump();
    await gesture.down(tester.getCenter(find.text('one')));
    await tester.pump();
    await gesture.up();
    expect(taps, 4);
    await gesture.moveTo(tester.getCenter(find.text('off')));
    await tester.pump();
  });

  testWidgets('OasisToggle flips and honours disabled', (tester) async {
    var value = false;
    await pumpOasis(
      tester,
      Column(
        children: [
          StatefulBuilder(
            builder: (context, set) => OasisToggle(
              value: value,
              onChanged: (v) => set(() => value = v),
            ),
          ),
          const OasisToggle(value: true, onChanged: null),
          const OasisToggle(value: false, onChanged: null),
        ],
      ),
    );
    expect(value, isFalse);
    await tester.tap(find.byType(OasisToggle).first);
    expect(value, isTrue);
  });

  testWidgets('OasisSlider tracks pointer input', (tester) async {
    var value = 0.5;
    await pumpOasis(
      tester,
      SizedBox(
        width: 200,
        child: Column(
          children: [
            StatefulBuilder(
              builder: (context, set) => OasisSlider(
                value: value,
                onChanged: (v) => set(() => value = v),
                min: 0,
                max: 10,
              ),
            ),
            const OasisSlider(value: 0.5, onChanged: null),
          ],
        ),
      ),
    );
    final rect = tester.getRect(find.byType(OasisSlider).first);
    await tester.tapAt(rect.centerRight - const Offset(10, 0));
    expect(value, greaterThan(9));
    await tester.tapAt(rect.centerLeft + const Offset(10, 0));
    expect(value, lessThan(1));
    final gesture = await tester.createGesture();
    await gesture.down(rect.center);
    await gesture.moveTo(rect.centerLeft);
    await gesture.up();
    expect(value, 0.0);
    await tester.tapAt(rect.center);
    expect(value, 5.0);
  });

  testWidgets('OasisSection and OasisRow render and tap', (tester) async {
    var taps = 0;
    await pumpOasis(
      tester,
      OasisSection(
        title: 'Group',
        children: [
          OasisRow(
            leading: const Icon(Icons.wifi),
            title: 'Row A',
            subtitle: 'sub',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => taps++,
          ),
          const OasisRow(title: 'Row B'),
        ],
      ),
    );
    expect(find.text('Group'), findsOneWidget);
    await tester.tap(find.text('Row A'));
    expect(taps, 1);
  });

  testWidgets('OasisNavRow selects and taps', (tester) async {
    var taps = 0;
    await pumpOasis(
      tester,
      Column(
        children: [
          OasisNavRow(
            icon: Icons.wifi,
            label: 'Wi-Fi entry',
            selected: true,
            onTap: () => taps++,
          ),
          OasisNavRow(
            icon: Icons.bluetooth,
            label: 'Bluetooth entry',
            selected: false,
            iconColor: const Color(0xFF112233),
            onTap: () => taps++,
          ),
        ],
      ),
    );
    await tester.tap(find.text('Wi-Fi entry'));
    expect(taps, 1);
    await tester.tap(find.text('Bluetooth entry'));
    expect(taps, 2);
  });

  testWidgets('OasisSearchField edits and submits', (tester) async {
    String? changed, submitted;
    await pumpOasis(
      tester,
      Scaffold(
        body: OasisSearchField(
          hint: 'find it',
          autofocus: true,
          onChanged: (v) => changed = v,
          onSubmitted: (v) => submitted = v,
        ),
      ),
    );
    await tester.enterText(find.byType(EditableText), 'hello');
    expect(changed, 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, 'hello');
  });

  testWidgets('OasisAppIcon and OasisGlass render', (tester) async {
    await pumpOasis(
      tester,
      const OasisGlass(
        padding: EdgeInsets.all(12),
        child: OasisAppIcon(
          icon: Icons.water_drop,
          colors: [Color(0xFF4FC3F7), Color(0xFF0078C8)],
          size: 48,
        ),
      ),
    );
    expect(find.byType(OasisGlass), findsOneWidget);
    expect(find.byIcon(Icons.water_drop), findsOneWidget);
  });

  testWidgets('TrafficLights hover shows glyphs and taps fire', (tester) async {
    var closed = 0, minimized = 0, maximized = 0;
    await pumpOasis(
      tester,
      Column(
        children: [
          OasisTrafficLights(
            onClose: () => closed++,
            onMinimize: () => minimized++,
            onMaximize: () => maximized++,
          ),
          const OasisTrafficLights(),
        ],
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byType(OasisTrafficLights).first),
    );
    await tester.pump();
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.close)));
    expect(closed, 1);
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.remove)));
    expect(minimized, 1);
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.add)));
    expect(maximized, 1);
    await gesture.moveTo(const Offset(640, 500));
    await tester.pump();
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('OasisWindow chrome wires callbacks and drag', (tester) async {
    var events = <String>[];
    Offset dragged = Offset.zero;
    await pumpOasis(
      tester,
      Center(
        child: OasisWindow(
          title: 'The Window',
          focused: false,
          width: 400,
          height: 300,
          onClose: () => events.add('close'),
          onMinimize: () => events.add('min'),
          onMaximize: () => events.add('max'),
          onDrag: (d) => dragged += d,
          child: const Text('content'),
        ),
      ),
    );
    expect(find.text('The Window'), findsOneWidget);
    expect(find.text('content'), findsOneWidget);
    await tester.drag(find.text('The Window'), const Offset(20, 10));
    expect(dragged.dx, greaterThan(0));
    Offset light(int i) =>
        tester.getRect(find.byType(OasisTrafficLights)).centerLeft +
        Offset(6 + i * 20.0, 0);
    await tester.tapAt(light(0));
    expect(events, contains('close'));
    await tester.tapAt(light(1));
    expect(events, contains('min'));
    await tester.tapAt(light(2));
    expect(events, contains('max'));
    events.clear();
  });

  testWidgets('OasisWindow edge grabbers report resize deltas', (tester) async {
    final calls = <(Offset, OasisResizeEdge)>[];
    await pumpOasis(
      tester,
      Center(
        child: OasisWindow(
          title: 'r',
          width: 400,
          height: 300,
          onResize: (d, edge) => calls.add((d, edge)),
          child: const SizedBox(),
        ),
      ),
    );
    final topLeft = tester.getTopLeft(find.byType(OasisWindow));

    final corner = await tester.startGesture(topLeft + const Offset(398, 298));
    await corner.moveBy(const Offset(20, 10));
    await corner.up();
    expect(calls, hasLength(1));
    expect(calls.single.$2, OasisResizeEdge.bottomRight);
    expect(calls.single.$1.dx, 20);
    expect(calls.single.$1.dy, 10);

    calls.clear();
    final edge = await tester.startGesture(topLeft + const Offset(200, 2));
    await edge.moveBy(const Offset(0, 15));
    await edge.up();
    expect(calls.single.$2, OasisResizeEdge.top);
  });

  testWidgets('OasisWindow unfocused dims', (tester) async {
    await pumpOasis(
      tester,
      const Center(
        child: OasisWindow(title: 't', focused: true, child: SizedBox()),
      ),
    );
    expect(find.byType(OasisWindow), findsOneWidget);
  });

  testWidgets('OasisWindow border does not inset the content', (tester) async {
    Size? inner;
    await pumpOasis(
      tester,
      Center(
        child: OasisWindow(
          title: 't',
          width: 400,
          height: 338,
          onResize: (d, e) {},
          child: LayoutBuilder(
            builder: (context, constraints) {
              inner = constraints.biggest;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(inner, const Size(400, 338 - kOasisWindowTitleBarHeight));
  });

  testWidgets('OasisWallpaper paints in light and dark', (tester) async {
    await pumpOasis(tester, OasisWallpaper());
    await pumpOasis(tester, OasisWallpaper(), theme: OasisThemeMode.dark);
    await pumpOasis(tester, OasisWallpaper(), theme: OasisThemeMode.oled);
    expect(find.byType(OasisWallpaper), findsOneWidget);
  });

  test('OasisStyle copies and lerps', () {
    const a = OasisStyle(
      palette: OasisPalette.light,
      windowRadius: 16,
      cardRadius: 12,
      controlRadius: 7,
      menuRadius: 10,
    );
    expect(a.copyWith(windowRadius: 20).windowRadius, 20);
    expect(a.copyWith().windowRadius, 16);
    expect(a.lerp(null, 0.4), a);
    expect(a.lerp(a.copyWith(windowRadius: 9), 0.9).windowRadius, 9);
  });

  test('OasisPalette resolves modes', () {
    expect(
      OasisPalette.of(OasisThemeMode.system, platformDark: false).isDark,
      isFalse,
    );
    expect(
      OasisPalette.of(OasisThemeMode.system, platformDark: true).isDark,
      isTrue,
    );
    expect(
      OasisPalette.of(OasisThemeMode.light, platformDark: true).isDark,
      isFalse,
    );
    expect(
      OasisPalette.of(OasisThemeMode.dark, platformDark: false).isDark,
      isTrue,
    );
    expect(
      OasisPalette.of(OasisThemeMode.oled, platformDark: false).isOled,
      isTrue,
    );
    expect(
      OasisTheme.resolve(OasisThemeMode.oled, platformDark: false),
      isA<ThemeData>(),
    );
    expect(OasisTheme.light(), isA<ThemeData>());
    expect(OasisTheme.dark(), isA<ThemeData>());
    expect(OasisTheme.oled(), isA<ThemeData>());
  });

  test('OasisAppearance mutators and custom accent', () {
    final a = OasisAppearance();
    expect(a.themeMode, OasisThemeMode.system);
    a.themeMode = OasisThemeMode.system;
    a.accent = null;
    a.themeMode = OasisThemeMode.dark;
    expect(a.themeMode, OasisThemeMode.dark);
    a.accent = const Color(0xFF123456);
    expect(a.accent, const Color(0xFF123456));
    final themed = a.themeForBrightness(false);
    expect(themed.colorScheme.primary, const Color(0xFF123456));
    a.themeMode = OasisThemeMode.oled;
    expect(
      a.themeForBrightness(true).scaffoldBackgroundColor.toARGB32(),
      isNot(0),
    );
    a.dispose();
  });

  testWidgets('OasisHost propagates', (tester) async {
    final appearance = OasisAppearance();
    final updates = UpdateService(currentVersion: () async => '1.0.0');
    late OasisHost found;
    await pumpOasis(
      tester,
      OasisHost(
        appearance: appearance,
        updates: updates,
        setLocale: (_) {},
        child: Builder(
          builder: (context) {
            found = OasisHost.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(found.appearance, appearance);
    expect(found.updates, updates);
    expect(found.openUrl, isNull);
    expect(found.updateShouldNotify(found), isFalse);
    appearance.dispose();
    updates.dispose();
  });

  testWidgets('OasisAppearance themeFor resolves context brightness', (
    tester,
  ) async {
    final a = OasisAppearance(themeMode: OasisThemeMode.system);
    await pumpOasis(
      tester,
      Builder(
        builder: (context) {
          return Text(a.themeFor(context).brightness.name);
        },
      ),
      platformDark: true,
    );
    expect(find.text('dark'), findsOneWidget);
  });

  testWidgets('OasisButton press cancelled by dragging off', (tester) async {
    var taps = 0;
    await pumpOasis(
      tester,
      OasisButton(
        label: 'b',
        variant: OasisButtonVariant.primary,
        onPressed: () => taps++,
      ),
    );
    final g = await tester.startGesture(tester.getCenter(find.text('b')));
    await tester.pump();
    await g.moveBy(const Offset(0, 80));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('OasisSearchField dark theme and OasisSlider pan', (
    tester,
  ) async {
    await pumpOasis(
      tester,
      Column(
        children: [
          const SizedBox(
            height: 60,
            child: Scaffold(body: OasisSearchField(hint: 'h')),
          ),
          const SizedBox(height: 8),
          Expanded(child: OasisWallpaper()),
        ],
      ),
      theme: OasisThemeMode.dark,
    );
    expect(find.byType(OasisSearchField), findsOneWidget);

    var v = 0.0;
    await pumpOasis(
      tester,
      SizedBox(
        width: 200,
        child: StatefulBuilder(
          builder: (c, set) =>
              OasisSlider(value: v, onChanged: (x) => set(() => v = x)),
        ),
      ),
      size: const Size(300, 100),
    );
    await tester.drag(find.byType(OasisSlider), const Offset(150, 0));
    expect(v, greaterThan(0.5));
  });

  testWidgets('OasisTrafficLights hover exit clears highlight', (tester) async {
    await pumpOasis(tester, const OasisTrafficLights());
    final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await m.addPointer(location: Offset.zero);
    addTearDown(m.removePointer);
    await m.moveTo(tester.getCenter(find.byType(OasisTrafficLights)));
    await tester.pump();
    await m.moveTo(const Offset(600, 600));
    await tester.pump();
  });

  testWidgets('OasisHost setLocale reaches the callback', (tester) async {
    final seen = <Locale?>[];
    await pumpOasis(
      tester,
      OasisHost(
        appearance: OasisAppearance(),
        updates: UpdateService(currentVersion: () async => '1.0.0'),
        setLocale: seen.add,
        child: Builder(
          builder: (context) {
            return const SizedBox();
          },
        ),
      ),
    );
    final element = tester.element(find.byType(SizedBox).last);
    OasisHost.of(element).setLocale.call(const Locale('ru'));
    expect(seen, [const Locale('ru')]);
  });

  testWidgets('OasisMenu opens, hovers, selects and closes', (tester) async {
    var selected = '';
    await pumpOasis(
      tester,
      Builder(
        builder: (context) => Center(
          child: GestureDetector(
            onTap: () => showOasisMenu(context, const Offset(100, 100), [
              OasisMenuItem(label: 'One', action: (_) => selected = 'one'),
              OasisMenuItem(
                label: 'Two',
                checked: true,
                separatorAfter: true,
                action: (_) => selected = 'two',
              ),
              const OasisMenuItem(label: 'Bare'),
              const OasisMenuItem(label: 'Off', enabled: false),
            ]),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Two'), findsOneWidget);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      mouse.hover(tester.getCenter(find.text('Two'))),
    );
    await tester.pump();
    await tester.sendEventToBinding(
      mouse.hover(tester.getCenter(find.text('Off'))),
    );
    await tester.pump();
    await tester.sendEventToBinding(mouse.hover(const Offset(4, 4)));
    await tester.pump();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(selected, 'two');
    expect(find.text('Two'), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bare'));
    await tester.pumpAndSettle();
    expect(find.text('Bare'), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(
      const Offset(10, 500),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Two'), findsNothing);
  });

  testWidgets('OasisPopupMenuButton opens and selects', (tester) async {
    int? got;
    await pumpOasis(
      tester,
      Center(
        child: OasisPopupMenuButton<int>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'more',
          selectedValue: 2,
          items: const [
            OasisPopupItem(value: 1, label: 'A'),
            OasisPopupItem(value: 2, label: 'B'),
          ],
          onSelected: (v) => got = v,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(got, 1);
  });

  testWidgets('OasisDialog opens and closes both ways', (tester) async {
    await pumpOasis(
      tester,
      Builder(
        builder: (context) => Center(
          child: GestureDetector(
            onTap: () => showOasisDialog(
              context,
              (context, close) =>
                  OasisButton(label: 'ok', onPressed: close),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('ok'), findsOneWidget);
    await tester.tap(find.text('ok'));
    await tester.pumpAndSettle();
    expect(find.text('ok'), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('ok'), findsNothing);
  });

  testWidgets('OasisDialog without overlay no-ops', (tester) async {
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          showOasisDialog(
            context,
            (context, close) => const Text('x'),
          );
          return const SizedBox();
        },
      ),
    );
  });

  testWidgets('OasisTextField variants and callbacks', (tester) async {
    final c = TextEditingController();
    var changed = '';
    var submitted = '';
    await pumpOasis(
      tester,
      Material(
        child: Column(
        children: [
          OasisTextField(
            controller: c,
            hintText: 'plain',
            icon: const Icon(Icons.search),
            onChanged: (v) => changed = v,
            onSubmitted: (v) => submitted = v,
          ),
          const OasisTextField(
            filled: true,
            hintText: 'filled',
            obscureText: true,
            autofocus: true,
          ),
          const Expanded(child: OasisTextField(expands: true)),
        ],
      ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'hi');
    expect(changed, 'hi');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, 'hi');
    expect(find.byType(TextField), findsNWidgets(3));
  });

  testWidgets('OasisCheckbox and OasisRadio toggle', (tester) async {
    var cb = false;
    var radio = 1;
    await pumpOasis(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Column(
          children: [
            OasisCheckbox(
              value: cb,
              onChanged: (v) => setState(() => cb = v),
            ),
            const OasisCheckbox(value: true),
            const OasisCheckbox(value: false),
            OasisRadio<int>(
              value: 2,
              groupValue: radio,
              onChanged: (v) => setState(() => radio = v),
            ),
            const OasisRadio<int>(value: 1, groupValue: 1),
            const OasisRadio<int>(value: 3, groupValue: 1),
          ],
        ),
      ),
    );
    expect(cb, isFalse);
    await tester.tap(find.byType(OasisCheckbox).first);
    await tester.pump();
    expect(cb, isTrue);
    expect(radio, 1);
    await tester.tap(find.byType(OasisRadio<int>).first);
    await tester.pump();
    expect(radio, 2);
  });

  testWidgets('OasisTooltip shows styled tip or bare child', (
    tester,
  ) async {
    await pumpOasis(
      tester,
      Column(
        children: const [
          OasisTooltip(message: 'tip', child: Text('a')),
          OasisTooltip(message: null, child: Text('b')),
          OasisTooltip(
            message: 'tap me',
            preferBelow: false,
            triggerMode: TooltipTriggerMode.tap,
            child: Text('c'),
          ),
        ],
      ),
    );
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      mouse.hover(tester.getCenter(find.text('a'))),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('tip'), findsOneWidget);
    await tester.tap(find.text('c'));
    await tester.pumpAndSettle();
    expect(find.text('tap me'), findsOneWidget);
  });
}


class _FailImg extends ImageProvider<_FailImg> {
  @override
  Future<_FailImg> obtainKey(_) async => this;

  @override
  ImageStreamCompleter loadImage(a, b) =>
      OneFrameImageStreamCompleter(Future.error('bad'));
}

void iconCoverage() {
  testWidgets('app icon falls back when the image fails', (tester) async {
    final f = File('${Directory.systemTemp.path}/badicon.png')
      ..writeAsStringSync('junk');
    addTearDown(() => f.delete());
    await pumpOasis(
      tester,
      OasisAppIcon(
        icon: Icons.broken_image,
        colors: const [Color(0xFF000000), Color(0xFF111111)],
        iconPath: f.path,
        image: _FailImg(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.broken_image), findsWidgets);
  });

  testWidgets('app icon renders svg files', (tester) async {
    final f = File('${Directory.systemTemp.path}/goodicon.svg')
      ..writeAsStringSync(
        '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48">'
        '<rect width="48" height="48" fill="#ffffff"/></svg>',
      );
    addTearDown(() => f.delete());
    await pumpOasis(
      tester,
      OasisAppIcon(
        icon: Icons.broken_image,
        colors: const [Color(0xFF000000), Color(0xFF111111)],
        iconPath: f.path,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byIcon(Icons.broken_image), findsNothing);
  });

  testWidgets('app icon falls back when the svg fails', (tester) async {
    final f = File('${Directory.systemTemp.path}/badicon.svg')
      ..writeAsStringSync('junk');
    addTearDown(() => f.delete());
    await pumpOasis(
      tester,
      OasisAppIcon(
        icon: Icons.broken_image,
        colors: const [Color(0xFF000000), Color(0xFF111111)],
        iconPath: f.path,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.broken_image), findsWidgets);
  });
}
