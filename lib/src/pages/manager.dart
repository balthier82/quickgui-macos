import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as path;
import 'package:version/version.dart';

import '../globals.dart';
import '../mixins/preferences_mixin.dart';
import '../model/osicons.dart';
import '../model/vminfo.dart';

/// VM manager page.
/// Displays a list of available VMs, running state and connection info,
/// with buttons to start and stop VMs.
class Manager extends StatefulWidget {
  const Manager({super.key});

  @override
  State<Manager> createState() => _ManagerState();
}

class _ManagerState extends State<Manager> with PreferencesMixin {
  List<String> _currentVms = [];
  Map<String, VmInfo> _activeVms = {};
  bool _spicy = false;
  List<String> _sshVms = [];
  String? _terminalEmulator;
  bool _refreshing = false;
  final List<String> _supportedTerminalEmulators = [
    if (Platform.isMacOS) 'osascript',
    'alacritty',
    'cool-retro-term',
    'gnome-terminal',
    'guake',
    'mate-terminal',
    'konsole',
    'lxterm',
    'lxterminal',
    'pterm',
    'sakura',
    'terminator',
    'tilix',
    'uxterm',
    'uxrvt',
    'xfce4-terminal',
    'xrvt',
    'xterm',
  ];
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    _getTerminalEmulator();
    _detectSpice();
    _getVms();
    refreshTimer = Timer.periodic(const Duration(seconds: 5), (Timer t) {
      _getVms();
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  void _getTerminalEmulator() async {
    // Find out which terminal emulator we have set as the default.
    String result = findExecutable('x-terminal-emulator') ?? '';
    if (result.isNotEmpty) {
      String terminalEmulator = await File(result).resolveSymbolicLinks();
      terminalEmulator = path.basenameWithoutExtension(terminalEmulator);
      if (_supportedTerminalEmulators.contains(terminalEmulator)) {
        setState(() {
          _terminalEmulator = path.basename(terminalEmulator);
        });
      }
    } else {
      // If x-terminal-emulator doesn't exist or returns empty, look for
      // supported terminals in the PATH
      for (String terminal in _supportedTerminalEmulators) {
        String? terminalPath = findExecutable(terminal);
        if (terminalPath != null) {
          setState(() {
            _terminalEmulator = terminal;
          });
          break;
        }
      }
    }
  }

  void _detectSpice() async {
    var result = findExecutable('spicy') ?? '';
    setState(() {
      _spicy = result.isNotEmpty;
    });
  }

  Future<VmInfo> _parseVmInfo(String name) async {
    VmInfo info = VmInfo();
    File portsFile = File(path.join(gWorkingDirectory, name, '$name.ports'));
    if (await portsFile.exists()) {
      List<String> lines = await portsFile.readAsLines();
      for (var line in lines) {
        List<String> parts = line.split(',');
        switch (parts[0]) {
          case 'ssh':
            info.sshPort = parts[1];
            break;
          case 'spice':
            info.spicePort = parts[1];
            break;
        }
      }
    }
    return info;
  }

  Future<bool> _isValidConf(String conf) async {
    List<String> lines = await File(conf).readAsLines();
    for (var line in lines) {
      List<String> parts = line.split('=');
      if (parts[0] == 'guest_os') {
        return true;
      }
    }
    return false;
  }

  Future<bool> _isRunning(String pid) async {
    try {
      var result = await Process.run(executablePath('kill'), ['-0', pid]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  Future<void> _getVms() async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    try {
      List<String> currentVms = [];
      Map<String, VmInfo> activeVms = {};

      await for (var entity in Directory(gWorkingDirectory)
          .list(recursive: false, followLinks: true)) {
        if (!entity.path.endsWith('.conf') || !await _isValidConf(entity.path)) {
          continue;
        }
        String name = path.basenameWithoutExtension(entity.path);
        currentVms.add(name);
        File pidFile = File(path.join(gWorkingDirectory, name, '$name.pid'));
        if (!await pidFile.exists()) {
          continue;
        }
        String pid = (await pidFile.readAsString()).trim();
        if (await _isRunning(pid)) {
          activeVms[name] =
              _activeVms[name] ?? await _parseVmInfo(name);
        }
      }
      currentVms.sort();

      var sshVms = <String>[];
      await Future.wait(activeVms.entries
          .where((entry) => entry.value.sshPort != null)
          .map((entry) async {
        if (await _detectSsh(int.parse(entry.value.sshPort!))) {
          sshVms.add(entry.key);
        }
      }));
      sshVms.sort();

      if (!mounted) {
        return;
      }
      setState(() {
        _currentVms = currentVms;
        _activeVms = activeVms;
        _sshVms = sshVms;
      });
    } finally {
      _refreshing = false;
    }
  }

  String _escapeAppleScript(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  Future<bool> _detectSsh(int port) async {
    const timeout = Duration(seconds: 2);
    Socket? socket;
    try {
      socket = await Socket.connect('localhost', port, timeout: timeout);
      return await socket
          .any((event) => utf8.decode(event).contains('SSH'))
          .timeout(timeout);
    } catch (exception) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  Widget _buildVmList() {
    List<Widget> widgetList = [];
    final Color buttonColor = Theme.of(context).colorScheme.primary;
    widgetList.addAll(
      [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "${context.t('Directory where the machines are stored')}:",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
                onPressed: () async {
                  var folder = await FilePicker.platform
                      .getDirectoryPath(dialogTitle: "Pick a folder");
                  if (folder != null) {
                    setState(() {
                      gWorkingDirectory = folder;
                    });
                    savePreference(prefWorkingDirectory, folder);
                    _getVms();
                  }
                },
                child: Text(gWorkingDirectory),
              ),
            ],
          ),
        ),
        const Divider(
          thickness: 2,
        ),
      ],
    );
    List<List<Widget>> rows = _currentVms.map((vm) {
      return _buildRow(vm, buttonColor);
    }).toList();
    for (var row in rows) {
      widgetList.addAll(row);
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: widgetList,
    );
  }

  List<Widget> _buildRow(String currentVm, Color buttonColor) {
    final bool active = _activeVms.containsKey(currentVm);
    final bool sshy = _sshVms.contains(currentVm);
    VmInfo vmInfo = VmInfo();
    String connectInfo = '';
    if (active) {
      vmInfo = _activeVms[currentVm]!;
      if (vmInfo.spicePort != null) {
        connectInfo += '${context.t('SPICE port')}: ${vmInfo.spicePort!} ';
      }
      if (vmInfo.sshPort != null && _terminalEmulator != null) {
        connectInfo += '${context.t('SSH port')}: ${vmInfo.sshPort!} ';
      }
    }
    String vmStem = currentVm;
    SvgPicture? osIcon;
    while (vmStem.contains('-')) {
      vmStem = vmStem.substring(0, vmStem.lastIndexOf('-'));
      if (osIcons.containsKey(vmStem)) {
        osIcon = SvgPicture.asset(
          osIcons[vmStem]!,
          width: 32,
          height: 32,
        );
        break;
      }
    }
    return <Widget>[
      ListTile(
          leading: osIcon ?? const Icon(Icons.computer, size: 32),
          title: Text(currentVm),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                  icon: Icon(
                    active ? Icons.play_arrow : Icons.play_arrow_outlined,
                    color: active ? Colors.green : buttonColor,
                    semanticLabel: active ? 'Running' : 'Run',
                  ),
                  onPressed: active
                      ? null
                      : () async {
                          List<String> arguments = [
                            '--vm',
                            '$currentVm.conf'
                          ];
                          if (_spicy) {
                            arguments.addAll(['--display', 'spice']);
                          }
                          await runCommand('quickemu', arguments,
                              workingDirectory: gWorkingDirectory);
                          VmInfo info = await _parseVmInfo(currentVm);
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _activeVms = {..._activeVms, currentVm: info};
                          });
                        }),
              IconButton(
                icon: Icon(
                  active ? Icons.stop : Icons.stop_outlined,
                  color: active ? Colors.red : null,
                  semanticLabel: active ? 'Stop' : 'Not running',
                ),
                onPressed: !active
                    ? null
                    : () {
                        showDialog<bool>(
                          context: context,
                          builder: (BuildContext context) => AlertDialog(
                            title: Text(context.t('Stop The Virtual Machine?')),
                            content: Text(context.t(
                                'You are about to terminate the virtual machine {0}',
                                args: [currentVm])),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(context.t('Cancel')),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(context.t('OK')),
                              ),
                            ],
                          ),
                        ).then((result) async {
                          result = result ?? false;
                          if (result) {
                            // If Quickemu is newer than 4.9.6, use the new --kill option
                            // which is macOS compatible.
                            var quickemuVersion =
                                Version.parse(await fetchQuickemuVersion());
                            if (quickemuVersion >= Version(4, 9, 6)) {
                              await runCommand(
                                  'quickemu', ['--vm', '$currentVm.conf', '--kill'],
                                  workingDirectory: gWorkingDirectory);
                            } else {
                              await runCommand('killall', [currentVm]);
                            }
                            if (!mounted) {
                              return;
                            }
                            setState(() {
                              _activeVms.remove(currentVm);
                            });
                          }
                        });
                      },
              ),
              IconButton(
                icon: Icon(Icons.delete,
                    color: active ? null : buttonColor,
                    semanticLabel: 'Delete'),
                onPressed: active
                    ? null
                    : () {
                        showDialog<String?>(
                          context: context,
                          builder: (BuildContext context) => AlertDialog(
                            title: Text(
                                context.t('Delete {0}', args: [currentVm])),
                            content: Text(
                              context.t(
                                  'You are about to delete {0}. This cannot be undone. Would you like to delete the disk image but keep the configuration, or delete the whole VM?',
                                  args: [currentVm]),
                            ),
                            actions: [
                              TextButton(
                                child: Text(context.t('Cancel')),
                                onPressed: () =>
                                    Navigator.pop(context, 'cancel'),
                              ),
                              TextButton(
                                child: Text(context.t('Delete disk image')),
                                onPressed: () => Navigator.pop(context, 'disk'),
                              ),
                              TextButton(
                                child: Text(context.t('Delete whole VM')),
                                onPressed: () => Navigator.pop(context, 'vm'),
                              ) // set up the AlertDialog
                            ],
                          ),
                        ).then((result) async {
                          result = result ?? 'cancel';
                          if (result != 'cancel') {
                            await runCommand('quickemu',
                                ['--vm', '$currentVm.conf', '--delete-$result'],
                                workingDirectory: gWorkingDirectory);
                            await _getVms();
                          }
                        });
                      },
              ),
            ],
          )),
      if (connectInfo.isNotEmpty)
        ListTile(
            title: Text(connectInfo, style: const TextStyle(fontSize: 12)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              IconButton(
                icon: Icon(
                  Icons.monitor,
                  color: _spicy ? buttonColor : null,
                  semanticLabel: 'Connect display with SPICE',
                ),
                tooltip: _spicy
                    ? context.t('Connect display with SPICE')
                    : context.t('SPICE client not found'),
                onPressed: !_spicy
                    ? null
                    : () {
                        runCommand('spicy', ['-p', vmInfo.spicePort!]);
                      },
              ),
              IconButton(
                icon: SvgPicture.asset('assets/images/console.svg',
                    semanticsLabel: 'Connect with SSH',
                    colorFilter: ColorFilter.mode(
                        sshy ? buttonColor : Colors.grey, BlendMode.srcIn)),
                tooltip: sshy
                    ? context.t('Connect with SSH')
                    : context.t('SSH server not detected on guest'),
                onPressed: !sshy
                    ? null
                    : () {
                        TextEditingController usernameController =
                            TextEditingController();
                        showDialog<bool>(
                          context: context,
                          builder: (BuildContext context) => AlertDialog(
                            title: Text(
                              context.t(
                                'Launch SSH connection to {0}',
                                args: [currentVm],
                              ),
                            ),
                            content: TextField(
                              controller: usernameController,
                              decoration: InputDecoration(
                                  hintText: context.t("SSH username")),
                            ),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(context.t('Cancel')),
                              ),
                              TextButton(
                                onPressed: () {
                                  if (usernameController.text.isEmpty) return;
                                  Navigator.of(context).pop(true);
                                },
                                child: Text(context.t('Connect')),
                              ),
                            ],
                          ),
                        ).then((result) {
                          result = result ?? false;
                          if (result) {
                            List<String> sshArgs = [
                              'ssh',
                              '-p',
                              vmInfo.sshPort!,
                              '${usernameController.text}@localhost'
                            ];
                            // Set the arguments to execute the ssh command in the default terminal.
                            // Strip the extension as x-terminal-emulator may point to a .wrapper
                            switch (path
                                .basenameWithoutExtension(_terminalEmulator!)) {
                              case 'osascript':
                                sshArgs = [
                                  '-e',
                                  'tell app "Terminal" to do script '
                                      '"${_escapeAppleScript(sshArgs.join(' '))}"'
                                ];
                                break;
                              case 'gnome-terminal':
                              case 'mate-terminal':
                                sshArgs.insert(0, '--');
                                break;
                              case 'alacritty':
                              case 'xterm':
                              case 'lxterm':
                              case 'uxterm':
                              case 'konsole':
                              case 'uxrvt':
                              case 'xrvt':
                              case 'sakura':
                              case 'cool-retro-term':
                              case 'pterm':
                              case 'lxterminal':
                              case 'tilix':
                                sshArgs.insert(0, '-e');
                                break;
                              case 'terminator':
                              case 'xfce4-terminal':
                                sshArgs.insert(0, '-x');
                                break;
                              case 'guake':
                                String command = sshArgs.join(' ');
                                sshArgs = ['-e', command];
                                break;
                            }
                            runCommand(_terminalEmulator!, sshArgs,
                                workingDirectory: gWorkingDirectory);
                          }
                        });
                      },
              ),
            ])),
      const Divider()
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Manager')),
      ),
      body: _buildVmList(),
    );
  }
}
