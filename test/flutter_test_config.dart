import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

const double _tolerance = 0.03;

class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    return result.passed || result.diffPercent <= _tolerance;
  }
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (goldenFileComparator is LocalFileComparator) {
    final current = goldenFileComparator as LocalFileComparator;
    goldenFileComparator =
        _TolerantComparator(current.basedir.resolve('test.dart'));
  }
  await testMain();
}
