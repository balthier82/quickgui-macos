import 'dart:io';

import 'package:process_run/shell.dart';

var gIsSnap = Platform.environment['SNAP']?.isNotEmpty ?? false;
const String prefWorkingDirectory = 'workingDirectory';
const String prefThemeMode = 'themeMode';
const String prefCurrentLocale = 'currentLocale';

bool gQuickgetFound = false;

String gWorkingDirectory = Directory.current.path;

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

final Map<String, String> _executableCache = {};

bool _isExecutable(String path) {
  var stat = FileStat.statSync(path);
  return stat.type == FileSystemEntityType.file && (stat.mode & 0x49) != 0;
}

String? findExecutable(String name) {
  var cached = _executableCache[name];
  if (cached != null) {
    return cached;
  }
  if (name.contains('/')) {
    return _isExecutable(name) ? (_executableCache[name] = name) : null;
  }
  for (var dir in gBinaryPaths) {
    var candidate = '$dir/$name';
    if (_isExecutable(candidate)) {
      return _executableCache[name] = candidate;
    }
  }
  return null;
}

String executablePath(String name) => findExecutable(name) ?? name;

Future<ProcessResult> runCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  var shell = Shell(
    environment: gEnvironment,
    workingDirectory: workingDirectory,
  );
  return shell.runExecutableArguments(executablePath(executable), arguments);
}

Future<String> fetchQuickemuVersion() async {
  try {
    var result = await runCommand('quickemu', ['--version']);
    if (result.exitCode == 0) {
      return (result.stdout as String).trim();
    }
  } on ProcessException {
    return '';
  } on ShellException {
    return '';
  }
  return '';
}
