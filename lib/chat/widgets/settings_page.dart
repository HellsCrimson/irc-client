import 'package:flutter/material.dart';

import '../models.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.isConnected,
    required this.isConnecting,
    required this.ipController,
    required this.portController,
    required this.nickController,
    required this.userController,
    required this.realnameController,
    required this.fingerprintController,
    required this.useTls,
    required this.tlsMode,
    required this.debugEnabled,
    required this.debugLines,
    required this.showRawMessages,
    required this.autoConnect,
    required this.themeMode,
    required this.onConnect,
    required this.onDisconnect,
    required this.onUseTlsChanged,
    required this.onTlsModeChanged,
    required this.onDebugChanged,
    required this.onShowRawMessagesChanged,
    required this.onThemeModeChanged,
    required this.onAutoConnectChanged,
  });

  final bool isConnected;
  final bool isConnecting;
  final TextEditingController ipController;
  final TextEditingController portController;
  final TextEditingController nickController;
  final TextEditingController userController;
  final TextEditingController realnameController;
  final TextEditingController fingerprintController;
  final bool useTls;
  final TlsMode tlsMode;
  final bool debugEnabled;
  final List<String> debugLines;
  final bool showRawMessages;
  final bool autoConnect;
  final ThemeMode themeMode;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final ValueChanged<bool> onUseTlsChanged;
  final ValueChanged<TlsMode?> onTlsModeChanged;
  final ValueChanged<bool> onDebugChanged;
  final ValueChanged<bool> onShowRawMessagesChanged;
  final ValueChanged<ThemeMode?> onThemeModeChanged;
  final ValueChanged<bool> onAutoConnectChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: TextField(
                controller: ipController,
                decoration: const InputDecoration(
                  labelText: 'Host/IP',
                  border: OutlineInputBorder(),
                ),
                enabled: !isConnected && !isConnecting,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                enabled: !isConnected && !isConnecting,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: ElevatedButton(
                onPressed: isConnecting
                    ? null
                    : (isConnected ? onDisconnect : onConnect),
                child: Text(isConnected ? 'Disconnect' : 'Connect'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: nickController,
                decoration: const InputDecoration(
                  labelText: 'Nick',
                  border: OutlineInputBorder(),
                ),
                enabled: !isConnected && !isConnecting,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: userController,
                decoration: const InputDecoration(
                  labelText: 'User',
                  border: OutlineInputBorder(),
                ),
                enabled: !isConnected && !isConnecting,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: realnameController,
          decoration: const InputDecoration(
            labelText: 'Real name (optional)',
            border: OutlineInputBorder(),
          ),
          enabled: !isConnected && !isConnecting,
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Switch(
              value: useTls,
              onChanged: isConnected || isConnecting
                  ? null
                  : (bool value) {
                      onUseTlsChanged(value);
                    },
            ),
            const Text('Use TLS'),
          ],
        ),
        Row(
          children: <Widget>[
            const Text('TLS verify:'),
            const SizedBox(width: 12),
            DropdownButton<TlsMode>(
              value: tlsMode,
              onChanged: !useTls || isConnected || isConnecting
                  ? null
                  : (TlsMode? value) {
                      onTlsModeChanged(value);
                    },
              items: const <DropdownMenuItem<TlsMode>>[
                DropdownMenuItem(
                  value: TlsMode.system,
                  child: Text('System'),
                ),
                DropdownMenuItem(
                  value: TlsMode.insecure,
                  child: Text('Insecure'),
                ),
                DropdownMenuItem(
                  value: TlsMode.fingerprint,
                  child: Text('Fingerprint'),
                ),
              ],
            ),
          ],
        ),
        if (useTls && tlsMode == TlsMode.fingerprint) ...<Widget>[
          const SizedBox(height: 8),
          TextField(
            controller: fingerprintController,
            decoration: const InputDecoration(
              labelText: 'SHA-1 Fingerprint',
              hintText: 'AA:BB:CC:... (40 hex)',
              border: OutlineInputBorder(),
            ),
            enabled: !isConnected && !isConnecting,
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Switch(
              value: debugEnabled,
              onChanged: (bool value) {
                onDebugChanged(value);
              },
            ),
            const Text('Debug logs'),
            const SizedBox(width: 8),
            if (!debugEnabled)
              const Text('(off)', style: TextStyle(color: Colors.grey)),
          ],
        ),
        Row(
          children: <Widget>[
            Switch(
              value: showRawMessages,
              onChanged: (bool value) {
                onShowRawMessagesChanged(value);
              },
            ),
            const Text('Show raw messages'),
          ],
        ),
        Row(
          children: <Widget>[
            const Text('Theme:'),
            const SizedBox(width: 12),
            DropdownButton<ThemeMode>(
              value: themeMode,
              onChanged: (ThemeMode? value) {
                onThemeModeChanged(value);
              },
              items: const <DropdownMenuItem<ThemeMode>>[
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('System'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text('Light'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text('Dark'),
                ),
              ],
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Switch(
              value: autoConnect,
              onChanged: (bool value) {
                onAutoConnectChanged(value);
              },
            ),
            const Text('Auto-connect on launch'),
          ],
        ),
        ExpansionTile(
          title: const Text('Debug'),
          initiallyExpanded: debugEnabled,
          children: <Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Text(
                debugLines.isEmpty
                    ? 'No debug output yet.'
                    : debugLines.join('\n'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
