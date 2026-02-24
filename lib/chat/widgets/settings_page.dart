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

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 0.9,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withOpacity(0.92),
              borderRadius: BorderRadius.circular(16),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.8,
      color: Theme.of(context).dividerTheme.color,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        _section(
          context,
          'Connection',
          <Widget>[
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: ipController,
                      decoration: const InputDecoration(
                        labelText: 'Host/IP',
                      ),
                      enabled: !isConnected && !isConnecting,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: portController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !isConnected && !isConnecting,
                    ),
                  ),
                ],
              ),
            ),
            _divider(context),
            Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isConnecting
                      ? null
                      : (isConnected ? onDisconnect : onConnect),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(isConnected ? 'Disconnect' : 'Connect'),
                ),
              ),
            ),
          ],
        ),
        _section(
          context,
          'Identity',
          <Widget>[
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: nickController,
                      decoration: const InputDecoration(
                        labelText: 'Nick',
                      ),
                      enabled: !isConnected && !isConnecting,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: userController,
                      decoration: const InputDecoration(
                        labelText: 'User',
                      ),
                      enabled: !isConnected && !isConnecting,
                    ),
                  ),
                ],
              ),
            ),
            _divider(context),
            Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(
                controller: realnameController,
                decoration: const InputDecoration(
                  labelText: 'Real name (optional)',
                ),
                enabled: !isConnected && !isConnecting,
              ),
            ),
          ],
        ),
        _section(
          context,
          'Security',
          <Widget>[
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  Switch(
                    value: useTls,
                    onChanged: isConnected || isConnecting
                        ? null
                        : (bool value) {
                            onUseTlsChanged(value);
                          },
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Use TLS',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            _divider(context),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
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
            ),
            if (useTls && tlsMode == TlsMode.fingerprint) ...<Widget>[
              _divider(context),
              Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: fingerprintController,
                  decoration: const InputDecoration(
                    labelText: 'SHA-1 Fingerprint',
                    hintText: 'AA:BB:CC:... (40 hex)',
                  ),
                  enabled: !isConnected && !isConnecting,
                ),
              ),
            ],
          ],
        ),
        _section(
          context,
          'Preferences',
          <Widget>[
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  Switch(
                    value: debugEnabled,
                    onChanged: (bool value) {
                      onDebugChanged(value);
                    },
                  ),
                  const SizedBox(width: 8),
                  const Text('Debug logs'),
                  const Spacer(),
                  if (!debugEnabled)
                    const Text('(off)', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            _divider(context),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  Switch(
                    value: showRawMessages,
                    onChanged: (bool value) {
                      onShowRawMessagesChanged(value);
                    },
                  ),
                  const SizedBox(width: 8),
                  const Text('Show raw messages'),
                ],
              ),
            ),
            _divider(context),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
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
            ),
            _divider(context),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  Switch(
                    value: autoConnect,
                    onChanged: (bool value) {
                      onAutoConnectChanged(value);
                    },
                  ),
                  const SizedBox(width: 8),
                  const Text('Auto-connect on launch'),
                ],
              ),
            ),
          ],
        ),
        _section(
          context,
          'Debug',
          <Widget>[
            ExpansionTile(
              title: const Text('Logs'),
              initiallyExpanded: debugEnabled,
              children: <Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
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
        ),
      ],
    );
  }
}
