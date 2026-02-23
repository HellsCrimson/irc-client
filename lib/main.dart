import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IRC Client',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0C4A6E)),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

enum MessageDirection {
  incoming,
  outgoing,
}

enum MessageKind {
  chat,
  system,
  raw,
}

enum TlsMode {
  system,
  insecure,
  fingerprint,
}

class ChatMessage {
  ChatMessage({
    required this.direction,
    required this.kind,
    required this.text,
    required this.timestamp,
    this.nick,
    this.channel,
    this.imageUrls = const <String>[],
  });

  final MessageDirection direction;
  final MessageKind kind;
  final String text;
  final DateTime timestamp;
  final String? nick;
  final String? channel;
  final List<String> imageUrls;
}

class IrcLine {
  IrcLine({
    required this.prefix,
    required this.command,
    required this.params,
    required this.trailing,
  });

  final String? prefix;
  final String command;
  final List<String> params;
  final String? trailing;

  String? get senderNick {
    if (prefix == null || prefix!.isEmpty) {
      return null;
    }
    return prefix!.contains('!') ? prefix!.split('!').first : prefix;
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _prefKeyIp = 'last_ip';
  static const _prefKeyPort = 'last_port';
  static const _prefKeyUseTls = 'use_tls';
  static const _prefKeyTlsMode = 'tls_mode';
  static const _prefKeyFingerprint = 'tls_fingerprint';
  static const _prefKeyNick = 'nick';
  static const _prefKeyUser = 'user';
  static const _prefKeyRealname = 'realname';
  static const _connectTimeout = Duration(seconds: 5);

  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _fingerprintController =
      TextEditingController();
  final TextEditingController _nickController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _realnameController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = <ChatMessage>[];
  final List<String> _debugLines = <String>[];

  ConnectionStatus _status = ConnectionStatus.disconnected;
  Socket? _socket;
  StreamSubscription<List<int>>? _socketSubscription;
  String _incomingBuffer = '';
  bool _useTls = false;
  TlsMode _tlsMode = TlsMode.system;
  bool _debugEnabled = true;
  int _currentTabIndex = 0;
  String _currentChannel = '';
  final List<String> _channels = <String>[];
  bool _showRawMessages = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    _disconnect();
    _ipController.dispose();
    _portController.dispose();
    _messageController.dispose();
    _fingerprintController.dispose();
    _nickController.dispose();
    _userController.dispose();
    _realnameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? lastIp = prefs.getString(_prefKeyIp);
    final int? lastPort = prefs.getInt(_prefKeyPort);
    final bool? useTls = prefs.getBool(_prefKeyUseTls);
    final String? tlsMode = prefs.getString(_prefKeyTlsMode);
    final String? fingerprint = prefs.getString(_prefKeyFingerprint);
    final String? nick = prefs.getString(_prefKeyNick);
    final String? user = prefs.getString(_prefKeyUser);
    final String? realname = prefs.getString(_prefKeyRealname);
    if (!mounted) {
      return;
    }
    setState(() {
      if (lastIp != null) {
        _ipController.text = lastIp;
      }
      if (lastPort != null) {
        _portController.text = lastPort.toString();
      }
      if (useTls != null) {
        _useTls = useTls;
      }
      if (tlsMode != null) {
        _tlsMode = _parseTlsMode(tlsMode);
      }
      if (fingerprint != null) {
        _fingerprintController.text = fingerprint;
      }
      if (nick != null) {
        _nickController.text = nick;
      }
      if (user != null) {
        _userController.text = user;
      }
      if (realname != null) {
        _realnameController.text = realname;
      }
    });
  }

  Future<void> _savePreferences(String ip, int port) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyIp, ip);
    await prefs.setInt(_prefKeyPort, port);
    await prefs.setBool(_prefKeyUseTls, _useTls);
    await prefs.setString(_prefKeyTlsMode, _tlsMode.name);
    await prefs.setString(
      _prefKeyFingerprint,
      _fingerprintController.text.trim(),
    );
    await prefs.setString(_prefKeyNick, _nickController.text.trim());
    await prefs.setString(_prefKeyUser, _userController.text.trim());
    await prefs.setString(_prefKeyRealname, _realnameController.text.trim());
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String? _validateInput() {
    final String ip = _ipController.text.trim();
    if (ip.isEmpty) {
      return 'IP address is required.';
    }
    final String portText = _portController.text.trim();
    final int? port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) {
      return 'Port must be between 1 and 65535.';
    }
    final String nick = _nickController.text.trim();
    if (nick.isEmpty) {
      return 'Nickname is required.';
    }
    final String user = _userController.text.trim();
    if (user.isEmpty) {
      return 'Username is required.';
    }
    if (_useTls && _tlsMode == TlsMode.fingerprint) {
      final String fingerprint = _normalizedFingerprint();
      if (fingerprint.isEmpty) {
        return 'Fingerprint is required for TLS pinning.';
      }
      if (fingerprint.length != 40) {
        return 'Fingerprint must be 40 hex characters (SHA-1).';
      }
    }
    return null;
  }

  Future<void> _connect() async {
    final String? validationError = _validateInput();
    if (validationError != null) {
      _showError(validationError);
      return;
    }

    final String ip = _ipController.text.trim();
    final int port = int.parse(_portController.text.trim());

    _setStatus(ConnectionStatus.connecting, reason: 'connect requested');
    final DateTime start = DateTime.now();
    _addDebug('Connecting to $ip:$port (TLS: ${_useTls ? _tlsModeLabel(_tlsMode) : 'off'})');

    try {
      final Socket socket = _useTls
          ? await _connectTls(ip, port)
          : await Socket.connect(
              ip,
              port,
              timeout: _connectTimeout,
            );
      _socket = socket;
      _addDebug('Connected in ${DateTime.now().difference(start).inMilliseconds} ms');
      await _savePreferences(ip, port);
      _listenToSocket(socket);
      _setStatus(ConnectionStatus.connected, reason: 'connected');
      _addSystemMessage(
        _useTls
            ? 'Connected to $ip:$port (TLS: ${_tlsModeLabel(_tlsMode)})'
            : 'Connected to $ip:$port',
      );
      _sendRegistration();
    } on SocketException catch (error) {
      _handleSocketError(
        'Connection failed: ${error.message} (osError: ${error.osError})',
      );
    } on TimeoutException {
      _handleSocketError(
        'Connection timed out after ${_connectTimeout.inSeconds}s.',
      );
    } catch (error) {
      _handleSocketError('Connection error: $error');
    }
  }

  Future<Socket> _connectTls(String ip, int port) async {
    switch (_tlsMode) {
      case TlsMode.system:
        return SecureSocket.connect(
          ip,
          port,
          timeout: _connectTimeout,
        );
      case TlsMode.insecure:
        return SecureSocket.connect(
          ip,
          port,
          timeout: _connectTimeout,
          onBadCertificate: (_) => true,
        );
      case TlsMode.fingerprint:
        final SecurityContext context =
            SecurityContext(withTrustedRoots: false);
        return SecureSocket.connect(
          ip,
          port,
          timeout: _connectTimeout,
          context: context,
          onBadCertificate: (X509Certificate cert) {
            final String expected = _normalizedFingerprint();
            final String actual = _normalizedSha1(cert);
            return actual.isNotEmpty && actual == expected;
          },
        );
    }
  }

  String _normalizedSha1(X509Certificate cert) {
    final Uint8List digest = cert.sha1;
    return _toHex(digest);
  }

  String _toHex(Uint8List bytes) {
    final StringBuffer buffer = StringBuffer();
    for (final int byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString().toLowerCase();
  }

  String _normalizedFingerprint() {
    final String raw = _fingerprintController.text.trim();
    return raw.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toLowerCase();
  }

  TlsMode _parseTlsMode(String value) {
    switch (value) {
      case 'insecure':
        return TlsMode.insecure;
      case 'fingerprint':
        return TlsMode.fingerprint;
      default:
        return TlsMode.system;
    }
  }

  String _tlsModeLabel(TlsMode mode) {
    switch (mode) {
      case TlsMode.system:
        return 'system';
      case TlsMode.insecure:
        return 'insecure';
      case TlsMode.fingerprint:
        return 'fingerprint';
    }
  }

  void _listenToSocket(Socket socket) {
    _socketSubscription = socket.listen(
      _handleIncomingData,
      onError: (Object error) {
        _addDebug('Socket stream error: $error');
        _handleSocketError('Socket error: $error');
      },
      onDone: () {
        _addDebug('Socket closed by remote.');
        _setStatus(ConnectionStatus.disconnected, reason: 'remote closed');
        _addSystemMessage('Disconnected.');
      },
      cancelOnError: true,
    );
  }

  void _handleIncomingData(List<int> data) {
    final String chunk = utf8.decode(data, allowMalformed: true);
    _incomingBuffer += chunk;
    while (true) {
      final int newlineIndex = _incomingBuffer.indexOf('\n');
      if (newlineIndex == -1) {
        break;
      }
      String line = _incomingBuffer.substring(0, newlineIndex);
      _incomingBuffer = _incomingBuffer.substring(newlineIndex + 1);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      if (line.isEmpty) {
        continue;
      }
      if (line.startsWith('PING')) {
        _addDebug('Received PING, replying PONG.');
        final String payload = line.substring(4).trimLeft();
        _sendRawLine(payload.isEmpty ? 'PONG' : 'PONG $payload');
        continue;
      }
      final bool handled = _handleIrcLine(line);
      if (!handled && _showRawMessages) {
        _addMessage(
          ChatMessage(
            direction: MessageDirection.incoming,
            kind: MessageKind.raw,
            text: line,
            timestamp: DateTime.now(),
          ),
        );
      }
    }
  }

  bool _handleIrcLine(String line) {
    final IrcLine? parsed = _parseIrcLine(line);
    if (parsed == null) {
      return false;
    }
    final String nick = _nickController.text.trim();
    final String? senderNick = parsed.senderNick;
    final String command = parsed.command;

    if (command == 'PRIVMSG' && parsed.params.isNotEmpty) {
      final String target = parsed.params.first;
      final String? message = parsed.trailing;
      if (message == null) {
        return false;
      }
      _addMessage(
        ChatMessage(
          direction: MessageDirection.incoming,
          kind: MessageKind.chat,
          text: message,
          imageUrls: _extractImageUrls(message),
          nick: senderNick ?? 'unknown',
          channel: target,
          timestamp: DateTime.now(),
        ),
      );
      return true;
    }

    if (command == 'NOTICE' && parsed.params.isNotEmpty) {
      final String? message = parsed.trailing;
      if (message == null) {
        return false;
      }
      _addSystemMessage('Notice from ${senderNick ?? 'server'}: $message');
      return true;
    }

    if (command == 'JOIN') {
      final String channel = parsed.trailing ??
          (parsed.params.isNotEmpty ? parsed.params.first : '');
      if (channel.isEmpty) {
        return false;
      }
      if (senderNick == nick) {
        setState(() {
          if (!_channels.contains(channel)) {
            _channels.add(channel);
          }
          _currentChannel = channel;
        });
        _addDebug('Auto-joined channel $channel');
      }
      _addSystemMessage('${senderNick ?? 'Someone'} joined $channel');
      return true;
    }

    if (command == 'PART' && parsed.params.isNotEmpty) {
      final String channel = parsed.params.first;
      if (senderNick == nick) {
        setState(() {
          _channels.remove(channel);
          if (_currentChannel == channel) {
            _currentChannel = _channels.isNotEmpty ? _channels.first : '';
          }
        });
        _addDebug('Auto-parted channel $channel');
      }
      _addSystemMessage('${senderNick ?? 'Someone'} left $channel');
      return true;
    }

    if (command == 'NICK') {
      final String? newNick = parsed.trailing ??
          (parsed.params.isNotEmpty ? parsed.params.first : null);
      if (newNick == null) {
        return false;
      }
      if (senderNick == nick) {
        _nickController.text = newNick;
      }
      _addSystemMessage(
        '${senderNick ?? 'Someone'} is now known as $newNick',
      );
      return true;
    }

    if (command == 'QUIT') {
      final String reason = parsed.trailing ?? 'Quit';
      _addSystemMessage('${senderNick ?? 'Someone'} quit ($reason)');
      return true;
    }

    if (command == 'ERROR') {
      final String reason = parsed.trailing ?? 'Server error';
      _addSystemMessage('Server error: $reason');
      return true;
    }

    return false;
  }

  IrcLine? _parseIrcLine(String line) {
    String? prefix;
    String? trailing;

    final int trailingIndex = line.indexOf(' :');
    if (trailingIndex != -1) {
      trailing = line.substring(trailingIndex + 2);
      line = line.substring(0, trailingIndex);
    }

    final List<String> tokens = line.split(' ');
    if (tokens.isEmpty) {
      return null;
    }

    int index = 0;
    if (tokens.first.startsWith(':')) {
      prefix = tokens.first.substring(1);
      index = 1;
    }
    if (index >= tokens.length) {
      return null;
    }
    final String command = tokens[index];
    final List<String> params =
        tokens.length > index + 1 ? tokens.sublist(index + 1) : <String>[];

    return IrcLine(
      prefix: prefix,
      command: command,
      params: params,
      trailing: trailing,
    );
  }

  void _handleSocketError(String message) {
    _setStatus(ConnectionStatus.error, reason: message);
    _addSystemMessage(message);
    _showError(message);
    _addDebug(message);
    _disconnect();
  }

  void _disconnect() {
    if (_socket != null) {
      _addDebug('Disconnect requested.');
    }
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _socket?.destroy();
    _socket = null;
    _incomingBuffer = '';
    _channels.clear();
    _currentChannel = '';
    if (mounted) {
      setState(() {
        if (_status != ConnectionStatus.error) {
          _status = ConnectionStatus.disconnected;
        }
      });
    }
  }

  void _setStatus(ConnectionStatus next, {String? reason}) {
    if (!mounted) {
      return;
    }
    if (_status != next) {
      _addDebug(
        'State: ${_status.name} -> ${next.name}${reason == null ? '' : ' ($reason)'}',
      );
    }
    setState(() {
      _status = next;
    });
  }

  void _sendRegistration() {
    final String nick = _nickController.text.trim();
    final String user = _userController.text.trim();
    final String realname =
        _realnameController.text.trim().isEmpty
            ? user
            : _realnameController.text.trim();
    _sendRawLine('NICK $nick');
    _sendRawLine('USER $user 0 * :$realname');
  }

  void _sendMessage() {
    if (_status != ConnectionStatus.connected || _socket == null) {
      _showError('Not connected.');
      return;
    }
    final String text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }
    if (text.startsWith('/')) {
      if (_handleCommand(text)) {
        _messageController.clear();
        return;
      }
    }
    if (_currentChannel.isEmpty) {
      _showError('Join a channel first (use /join).');
      return;
    }
    _sendRawLine('PRIVMSG $_currentChannel :$text');
    _addMessage(
      ChatMessage(
        direction: MessageDirection.outgoing,
        kind: MessageKind.chat,
        text: text,
        imageUrls: _extractImageUrls(text),
        nick: _nickController.text.trim(),
        channel: _currentChannel,
        timestamp: DateTime.now(),
      ),
    );
    _messageController.clear();
  }

  bool _handleCommand(String text) {
    if (!text.startsWith('/')) {
      return false;
    }
    final String trimmed = text.substring(1).trim();
    if (trimmed.isEmpty) {
      _showError('Command is empty.');
      return true;
    }
    final List<String> parts = trimmed.split(RegExp(r'\s+'));
    final String command = parts.first.toLowerCase();
    final String args =
        parts.length > 1 ? trimmed.substring(command.length).trim() : '';

    switch (command) {
      case 'nick':
        if (args.isEmpty) {
          _showError('Usage: /nick <nickname>');
          return true;
        }
        _sendRawLine('NICK $args');
        _addSystemMessage('Nick set to $args');
        _nickController.text = args;
        return true;
      case 'join':
        if (args.isEmpty) {
          _showError('Usage: /join <#channel>');
          return true;
        }
        _sendRawLine('JOIN $args');
        final String channel = args.split(RegExp(r'\s+')).first;
        setState(() {
          if (!_channels.contains(channel)) {
            _channels.add(channel);
          }
          _currentChannel = channel;
        });
        _addSystemMessage('Joining $channel');
        _addDebug('Current channel set to $_currentChannel');
        return true;
      case 'part':
        if (args.isEmpty) {
          _showError('Usage: /part <#channel>');
          return true;
        }
        final String channel = args.split(RegExp(r'\s+')).first;
        _sendRawLine('PART $channel');
        setState(() {
          _channels.remove(channel);
          if (_currentChannel == channel) {
            _currentChannel = _channels.isNotEmpty ? _channels.first : '';
          }
        });
        _addSystemMessage('Leaving $channel');
        _addDebug('Parted channel $channel');
        return true;
      case 'msg':
        if (args.isEmpty) {
          _showError('Usage: /msg <target> <message>');
          return true;
        }
        final List<String> msgParts = args.split(RegExp(r'\s+'));
        if (msgParts.length < 2) {
          _showError('Usage: /msg <target> <message>');
          return true;
        }
        final String target = msgParts.first;
        final String message = args.substring(target.length).trim();
        _sendRawLine('PRIVMSG $target :$message');
        _addMessage(
          ChatMessage(
            direction: MessageDirection.outgoing,
            kind: MessageKind.chat,
            text: message,
            imageUrls: _extractImageUrls(message),
            nick: _nickController.text.trim(),
            channel: target,
            timestamp: DateTime.now(),
          ),
        );
        return true;
      case 'user':
        if (args.isEmpty) {
          _showError('Usage: /user <username> [realname]');
          return true;
        }
        final List<String> userParts = args.split(RegExp(r'\s+'));
        final String username = userParts.first;
        final String realname = userParts.length > 1
            ? args.substring(username.length).trim()
            : username;
        _sendRawLine('USER $username 0 * :$realname');
        return true;
      default:
        _showError('Unknown command: /$command');
        return true;
    }
  }

  void _sendRawLine(String line) {
    _socket!.write('$line\n');
    if (_showRawMessages) {
      _addMessage(
        ChatMessage(
          direction: MessageDirection.outgoing,
          kind: MessageKind.raw,
          text: line,
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  void _addMessage(ChatMessage message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _messages.add(message);
    });
    _scrollToBottom();
  }

  void _addSystemMessage(String text) {
    _addMessage(
      ChatMessage(
        direction: MessageDirection.incoming,
        kind: MessageKind.system,
        text: text,
        timestamp: DateTime.now(),
      ),
    );
  }

  void _addDebug(String line) {
    if (!_debugEnabled) {
      return;
    }
    final String timestamp = _formatTimestamp(DateTime.now());
    setState(() {
      _debugLines.add('[$timestamp] $line');
      if (_debugLines.length > 100) {
        _debugLines.removeAt(0);
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      final double target = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Color _statusColor() {
    switch (_status) {
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.connecting:
        return Colors.orange;
      case ConnectionStatus.error:
        return Colors.red;
      case ConnectionStatus.disconnected:
        return Colors.grey;
    }
  }

  String _statusLabel() {
    switch (_status) {
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.connecting:
        return 'Connecting...';
      case ConnectionStatus.error:
        return 'Error';
      case ConnectionStatus.disconnected:
        return 'Disconnected';
    }
  }

  Widget _buildMessageTile(ChatMessage message) {
    if (message.kind == MessageKind.system) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFCBD5F5)),
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFFF8FAFC),
        ),
        child: Text(
          message.text,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    }

    if (message.kind == MessageKind.raw) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: const Color(0xFFF1F5F9),
        child: Text(
          message.text,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      );
    }

    final bool isOutgoing = message.direction == MessageDirection.outgoing;
    final Color bubbleColor = isOutgoing
        ? const Color(0xFF0C4A6E)
        : const Color(0xFFE2E8F0);
    final Color textColor = isOutgoing ? Colors.white : Colors.black87;
    final Alignment alignment =
        isOutgoing ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _formatTimestamp(message.timestamp),
                  style: TextStyle(
                    color: textColor.withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 6),
                if (!isOutgoing && message.nick != null)
                  Text(
                    '${message.nick}:',
                    style: TextStyle(
                      color: _colorForNick(message.nick!),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              message.text,
              style: TextStyle(color: textColor, fontSize: 15),
              softWrap: true,
            ),
            if (message.imageUrls.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              ...message.imageUrls.map(
                (String url) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GestureDetector(
                      onTap: () => _openImageViewer(url),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (BuildContext context, Object error,
                            StackTrace? stackTrace) {
                          return Container(
                            color: const Color(0xFFE2E8F0),
                            padding: const EdgeInsets.all(8),
                            child: const Text('Image failed to load.'),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            if (!isOutgoing && message.channel != null)
              Text(
                message.channel!,
                style: TextStyle(
                  color: textColor.withOpacity(0.6),
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final String hour = time.hour.toString().padLeft(2, '0');
    final String minute = time.minute.toString().padLeft(2, '0');
    final String second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  Color _colorForNick(String nick) {
    const List<Color> palette = <Color>[
      Color(0xFF2563EB),
      Color(0xFF0F766E),
      Color(0xFFB45309),
      Color(0xFF9333EA),
      Color(0xFFDC2626),
      Color(0xFF0EA5E9),
      Color(0xFF16A34A),
      Color(0xFFDB2777),
      Color(0xFF64748B),
    ];
    final int hash = _stableHash(nick);
    return palette[hash % palette.length];
  }

  int _stableHash(String input) {
    int hash = 0;
    for (int i = 0; i < input.length; i++) {
      hash = (hash * 31 + input.codeUnitAt(i)) & 0x7fffffff;
    }
    return hash;
  }

  void _openImageViewer(String url) {
    if (!mounted) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: Colors.black,
          child: Stack(
            children: <Widget>[
              InteractiveViewer(
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (BuildContext context, Object error,
                        StackTrace? stackTrace) {
                      return Container(
                        color: Colors.black,
                        padding: const EdgeInsets.all(16),
                        child: const Text(
                          'Image failed to load.',
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<String> _extractImageUrls(String text) {
    final RegExp regex = RegExp(
      r'(https?:\/\/[^\s]+?\.(?:png|jpe?g|gif|webp))',
      caseSensitive: false,
    );
    return regex
        .allMatches(text)
        .map((RegExpMatch match) => match.group(1))
        .whereType<String>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bool canConnect = _status == ConnectionStatus.disconnected ||
        _status == ConnectionStatus.error;
    final bool isConnecting = _status == ConnectionStatus.connecting;
    final bool isConnected = _status == ConnectionStatus.connected;

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTabIndex == 0 ? 'Chat' : 'Connection'),
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: _currentTabIndex == 0
              ? _buildChatPage(isConnected)
              : _buildSettingsPage(isConnected, isConnecting, canConnect),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: (int index) {
          setState(() {
            _currentTabIndex = index;
          });
        },
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Connection',
          ),
        ],
      ),
    );
  }

  Widget _buildChatPage(bool isConnected) {
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFFE2E8F0),
          child: Row(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _statusColor(),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(_statusLabel()),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFFF8FAFC),
          child: Row(
            children: <Widget>[
              const Text('Channel:'),
              const SizedBox(width: 8),
              if (_channels.isEmpty)
                const Text('None (use /join)'),
              if (_channels.isNotEmpty)
                Expanded(
                  child: DropdownButton<String>(
                    value:
                        _currentChannel.isEmpty ? _channels.first : _currentChannel,
                    isExpanded: true,
                    onChanged: (String? value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _currentChannel = value;
                      });
                    },
                    items: _channels
                        .map(
                          (String channel) => DropdownMenuItem<String>(
                            value: channel,
                            child: Text(channel),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _messages.isEmpty
              ? const Center(child: Text('No messages yet.'))
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: _messages.length,
                  itemBuilder: (BuildContext context, int index) {
                    return _buildMessageTile(_messages[index]);
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    labelText: 'Message (or /nick, /join, /part, /user, /msg)',
                    border: OutlineInputBorder(),
                  ),
                  enabled: isConnected,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: isConnected ? _sendMessage : null,
                child: const Text('Send'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsPage(
    bool isConnected,
    bool isConnecting,
    bool canConnect,
  ) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: TextField(
                controller: _ipController,
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
                controller: _portController,
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
                onPressed:
                    isConnecting ? null : (isConnected ? _disconnect : _connect),
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
                controller: _nickController,
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
                controller: _userController,
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
          controller: _realnameController,
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
              value: _useTls,
              onChanged: isConnected || isConnecting
                  ? null
                  : (bool value) {
                      setState(() {
                        _useTls = value;
                      });
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
              value: _tlsMode,
              onChanged: !_useTls || isConnected || isConnecting
                  ? null
                  : (TlsMode? value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _tlsMode = value;
                      });
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
        if (_useTls && _tlsMode == TlsMode.fingerprint) ...<Widget>[
          const SizedBox(height: 8),
          TextField(
            controller: _fingerprintController,
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
              value: _debugEnabled,
              onChanged: (bool value) {
                setState(() {
                  _debugEnabled = value;
                });
              },
            ),
            const Text('Debug logs'),
            const SizedBox(width: 8),
            if (!_debugEnabled)
              const Text('(off)', style: TextStyle(color: Colors.grey)),
          ],
        ),
        Row(
          children: <Widget>[
            Switch(
              value: _showRawMessages,
              onChanged: (bool value) {
                setState(() {
                  _showRawMessages = value;
                });
              },
            ),
            const Text('Show raw messages'),
          ],
        ),
        ExpansionTile(
          title: const Text('Debug'),
          initiallyExpanded: _debugEnabled,
          children: <Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: const Color(0xFFF1F5F9),
              child: Text(
                _debugLines.isEmpty
                    ? 'No debug output yet.'
                    : _debugLines.join('\n'),
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
