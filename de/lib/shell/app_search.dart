import 'package:oasis_ui/oasis_ui.dart';

/// Ranks [apps] for the launcher and app grid: launch count first for an
/// empty query, otherwise a fuzzy prefix/substring score over the app
/// name, generic name and keywords.
List<OasisApp> rankApps(
  List<OasisApp> apps,
  Map<String, int> launchCounts,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    final order = {for (var i = 0; i < apps.length; i++) apps[i].id: i};
    final sorted = [...apps]
      ..sort((a, b) {
        final byCount = (launchCounts[b.id] ?? 0).compareTo(
          launchCounts[a.id] ?? 0,
        );
        return byCount != 0 ? byCount : order[a.id]! - order[b.id]!;
      });
    return sorted;
  }
  bool fuzzy(String field) {
    var i = 0;
    for (final ch in field.codeUnits) {
      if (i < q.length && ch == q.codeUnitAt(i)) i++;
    }
    return i == q.length;
  }

  int score(OasisApp a) {
    var best = 0;
    final fields = [a.name, ?a.genericName, ...a.keywords];
    for (var i = 0; i < fields.length; i++) {
      final f = fields[i].toLowerCase();
      final tier = f.startsWith(q)
          ? 3
          : f.contains(q)
          ? 2
          : fuzzy(f)
          ? 1
          : 0;
      if (tier == 0) continue;
      final s = tier * 2 + (i == 0 ? 1 : 0);
      if (s > best) best = s;
    }
    return best;
  }

  final scored = <(OasisApp, int)>[];
  for (final a in apps) {
    final s = score(a);
    if (s > 0) scored.add((a, s));
  }
  scored.sort((x, y) {
    final byScore = y.$2.compareTo(x.$2);
    if (byScore != 0) return byScore;
    final byRecency = (launchCounts[y.$1.id] ?? 0).compareTo(
      launchCounts[x.$1.id] ?? 0,
    );
    if (byRecency != 0) return byRecency;
    return x.$1.name.compareTo(y.$1.name);
  });
  return [for (final s in scored) s.$1];
}

/// Splits a user-entered command line on unquoted whitespace, honoring
/// single and double quotes.
List<String> splitArgv(String command) {
  final argv = <String>[];
  final buf = StringBuffer();
  String? quote;
  for (var i = 0; i < command.length; i++) {
    final ch = command[i];
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else {
        buf.write(ch);
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
    } else if (ch == ' ' || ch == '\t') {
      if (buf.isNotEmpty) {
        argv.add(buf.toString());
        buf.clear();
      }
    } else {
      buf.write(ch);
    }
  }
  if (buf.isNotEmpty) argv.add(buf.toString());
  return argv;
}
