import 'dart:io';

var gIsSnap = Platform.environment['SNAP']?.isNotEmpty ?? false;
const String prefWorkingDirectory = 'workingDirectory';
const String prefThemeMode = 'themeMode';
const String prefCurrentLocale = 'currentLocale';

final List<String> _extraBinaryPaths = [
  '/opt/homebrew/bin',
  '/opt/homebrew/sbin',
  '/usr/local/bin',
  '/usr/local/sbin',
  '/opt/local/bin',
  '/opt/local/sbin',
  if (Platform.environment['HOME'] != null)
    '${Platform.environment['HOME']}/.local/bin',
];

final List<String> gBinaryPaths = () {
  var paths = (Platform.environment['PATH'] ?? '')
      .split(':')
      .where((element) => element.isNotEmpty)
      .toList();
  for (var extra in _extraBinaryPaths) {
    if (!paths.contains(extra) && Directory(extra).existsSync()) {
      paths.add(extra);
    }
  }
  return paths;
}();

final Map<String, String> gEnvironment = {
  ...Platform.environment,
  'PATH': gBinaryPaths.join(':'),
};

final Map<String, String?> _executableCache = {};

String? findExecutable(String name) {
  return _executableCache.putIfAbsent(name, () {
    if (name.contains('/')) {
      return File(name).existsSync() ? name : null;
    }
    for (var dir in gBinaryPaths) {
      var candidate = '$dir/$name';
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  });
}

String executablePath(String name) => findExecutable(name) ?? name;

Future<String> fetchQuickemuVersion() async {
  try {
    var result = await Process.run(executablePath('quickemu'), ['--version'],
        environment: gEnvironment);
    if (result.exitCode == 0) {
      return result.stdout.trim();
    }
  } on ProcessException {
    return '';
  }
  return '';
}
