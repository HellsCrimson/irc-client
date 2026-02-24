import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';
import 'utils/image_utils.dart';
import 'utils/irc_parser.dart';
import 'utils/time_utils.dart';
import 'utils/tls_utils.dart';
import 'widgets/chat_page.dart';
import 'widgets/message_tile.dart';
import 'widgets/settings_page.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  static const String _statusChannel = '_status';
  static const _prefKeyIp = 'last_ip';
  static const _prefKeyPort = 'last_port';
  static const _prefKeyUseTls = 'use_tls';
  static const _prefKeyTlsMode = 'tls_mode';
  static const _prefKeyFingerprint = 'tls_fingerprint';
  static const _prefKeyNick = 'nick';
  static const _prefKeyUser = 'user';
  static const _prefKeyRealname = 'realname';
  static const _prefKeyAutoConnect = 'auto_connect';
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
  bool _autoConnect = false;
  final Map<String, List<ChatMessage>> _channelMessages =
      <String, List<ChatMessage>>{};
  final Set<String> _joinedChannels = <String>{};
  bool _listRequestedManually = false;
  bool _registrationComplete = false;
  final List<String> _motdLines = <String>[];
  int _nextMessageId = 0;
  final Map<int, Set<String>> _loadedImageUrlsByMessageId =
      <int, Set<String>>{};
  final Map<int, Map<String, String>> _imageUrlAliasesByMessageId =
      <int, Map<String, String>>{};
  bool _wasConnectedBeforeBackground = false;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;
  bool _manualDisconnectInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPreferences();
    _initNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disconnect(manual: true);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _wasConnectedBeforeBackground =
          _status == ConnectionStatus.connected && _socket != null;
      if (_wasConnectedBeforeBackground) {
        _addSystemMessage('App backgrounded. Connection may drop.',
            channel: _statusChannel);
      }
    }

    if (state == AppLifecycleState.resumed) {
      if (_wasConnectedBeforeBackground &&
          _status != ConnectionStatus.connected) {
        _addSystemMessage('Reconnecting after background...',
            channel: _statusChannel);
        _connect();
      }
      _wasConnectedBeforeBackground = false;
    }
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
    final bool? autoConnect = prefs.getBool(_prefKeyAutoConnect);
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
      if (autoConnect != null) {
        _autoConnect = autoConnect;
      }
    });

    if (_autoConnect && _canAutoConnect()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_status == ConnectionStatus.disconnected) {
          _connect();
        }
      });
    }
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _notificationsPlugin.initialize(initSettings);
    _notificationsReady = true;
  }

  Future<void> _notifyConnectionLost({String? reason}) async {
    if (!_notificationsReady) {
      return;
    }
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'connection',
      'Connection',
      importance: Importance.high,
      priority: Priority.high,
    );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();
    const NotificationDetails details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _notificationsPlugin.show(
      1,
      'Connection lost',
      reason ?? 'Disconnected from server.',
      details,
    );
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
    await prefs.setBool(_prefKeyAutoConnect, _autoConnect);
  }

  bool _canAutoConnect() {
    final String ip = _ipController.text.trim();
    final int? port = int.tryParse(_portController.text.trim());
    final String nick = _nickController.text.trim();
    final String user = _userController.text.trim();
    if (ip.isEmpty || port == null || port < 1 || port > 65535) {
      return false;
    }
    if (nick.isEmpty || user.isEmpty) {
      return false;
    }
    if (_useTls && _tlsMode == TlsMode.fingerprint) {
      return normalizedFingerprint(_fingerprintController.text).length == 40;
    }
    return true;
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
      final String fingerprint =
          normalizedFingerprint(_fingerprintController.text);
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
    _addDebug(
        'Connecting to $ip:$port (TLS: ${_useTls ? _tlsModeLabel(_tlsMode) : 'off'})');

    try {
      final Socket socket = _useTls
          ? await _connectTls(ip, port)
          : await Socket.connect(
              ip,
              port,
              timeout: _connectTimeout,
            );
      _socket = socket;
      _addDebug(
          'Connected in ${DateTime.now().difference(start).inMilliseconds} ms');
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
            final String expected =
                normalizedFingerprint(_fingerprintController.text);
            final String actual = normalizedSha1(cert);
            return actual.isNotEmpty && actual == expected;
          },
        );
    }
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
        if (!_manualDisconnectInProgress) {
          _notifyConnectionLost(reason: 'Server closed the connection.');
        }
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
            id: _nextMessageId++,
            direction: MessageDirection.incoming,
            kind: MessageKind.raw,
            text: line,
            timestamp: DateTime.now(),
          ),
          channel: _statusChannel,
        );
      }
    }
  }

  bool _handleIrcLine(String line) {
    final IrcLine? parsed = parseIrcLine(line);
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
      final String messageChannel = isChannel(target)
          ? target
          : (senderNick ?? target);
      if (!_channels.contains(messageChannel)) {
        setState(() {
          _channels.add(messageChannel);
        });
      }
      final ImageParseResult imageParsed = extractImageUrls(message);
      _addMessage(
        ChatMessage(
          id: _nextMessageId++,
          direction: MessageDirection.incoming,
          kind: MessageKind.chat,
          text: message,
          imageUrls: imageParsed.urls,
          nick: senderNick ?? 'unknown',
          channel: messageChannel,
          timestamp: DateTime.now(),
        ),
        imageAliases: imageParsed.aliases,
      );
      return true;
    }

    if (command == 'NOTICE' && parsed.params.isNotEmpty) {
      final String target = parsed.params.first;
      final String? message = parsed.trailing;
      if (message == null) {
        return false;
      }
      if (isChannel(target) && !_channels.contains(target)) {
        setState(() {
          _channels.add(target);
        });
      }
      _addSystemMessage(
        'Notice from ${senderNick ?? 'server'}: $message',
        channel: isChannel(target) ? target : _statusChannel,
      );
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
        _joinedChannels.add(channel);
        _addDebug('Auto-joined channel $channel');
      }
      _addSystemMessage('${senderNick ?? 'Someone'} joined $channel',
          channel: channel);
      return true;
    }

    if (command == 'PART' && parsed.params.isNotEmpty) {
      final String channel = parsed.params.first;
      if (senderNick == nick) {
        _joinedChannels.remove(channel);
        _addDebug('Auto-parted channel $channel');
      }
      _addSystemMessage('${senderNick ?? 'Someone'} left $channel',
          channel: channel);
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

    if (RegExp(r'^\d{3}$').hasMatch(command)) {
      return _handleNumeric(command, parsed);
    }

    return false;
  }

  bool _handleNumeric(String code, IrcLine parsed) {
    if (code == '001') {
      _registrationComplete = true;
      if (_autoConnect) {
        _requestChannelList(auto: true);
      }
      return true;
    }

    if (code == '321') {
      setState(() {
        _channels
          ..clear()
          ..addAll(_joinedChannels);
      });
      _addDebug('Channel list start.');
      return true;
    }

    if (code == '322') {
      if (parsed.params.length >= 2) {
        final String channel = parsed.params[1];
        if (channel.isNotEmpty && !_channels.contains(channel)) {
          setState(() {
            _channels.add(channel);
          });
        }
        return true;
      }
    }

    if (code == '323') {
      if (_listRequestedManually) {
        _addSystemMessage('Channel list updated (${_channels.length}).');
        _listRequestedManually = false;
      }
      _addDebug('Channel list end.');
      return true;
    }

    if (code == '372') {
      if (parsed.trailing != null && parsed.trailing!.isNotEmpty) {
        _motdLines.add(parsed.trailing!);
      }
      return true;
    }

    if (code == '376' || code == '422') {
      if (_motdLines.isNotEmpty) {
        _addSystemMessage(
          'MOTD:\n${_motdLines.join('\n')}',
          channel: _statusChannel,
        );
        _motdLines.clear();
      }
      return true;
    }

    return false;
  }

  void _handleSocketError(String message) {
    _setStatus(ConnectionStatus.error, reason: message);
    _addSystemMessage(message);
    _showError(message);
    _addDebug(message);
    if (!_manualDisconnectInProgress) {
      _notifyConnectionLost(reason: message);
    }
    _disconnect();
  }

  void _disconnect({bool manual = false}) {
    if (manual) {
      _manualDisconnectInProgress = true;
    }
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
    _channelMessages.clear();
    _joinedChannels.clear();
    _listRequestedManually = false;
    _registrationComplete = false;
    _motdLines.clear();
    _loadedImageUrlsByMessageId.clear();
    _imageUrlAliasesByMessageId.clear();
    if (mounted) {
      setState(() {
        if (_status != ConnectionStatus.error) {
          _status = ConnectionStatus.disconnected;
        }
      });
    }
    if (manual) {
      _manualDisconnectInProgress = false;
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

  void _requestChannelList({required bool auto}) {
    if (_status != ConnectionStatus.connected || _socket == null) {
      if (!auto) {
        _showError('Not connected.');
      }
      return;
    }
    if (auto && !_registrationComplete) {
      _addDebug('Deferring channel list until registration completes.');
      return;
    }
    _listRequestedManually = !auto;
    setState(() {
      _channels
        ..clear()
        ..addAll(_joinedChannels);
    });
    _sendRawLine('LIST');
    if (auto) {
      _addDebug('Requested channel list (auto).');
    } else {
      _addSystemMessage('Requested channel list.');
    }
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
    if (_currentChannel.isEmpty || _currentChannel == _statusChannel) {
      _showError('Join a channel first (use /join).');
      return;
    }
    if (!_joinedChannels.contains(_currentChannel)) {
      _showError('You are not in $_currentChannel yet.');
      return;
    }
    _sendRawLine('PRIVMSG $_currentChannel :$text');
    final ImageParseResult parsed = extractImageUrls(text);
    _addMessage(
      ChatMessage(
        id: _nextMessageId++,
        direction: MessageDirection.outgoing,
        kind: MessageKind.chat,
        text: text,
        imageUrls: parsed.urls,
        nick: _nickController.text.trim(),
        channel: _currentChannel,
        timestamp: DateTime.now(),
      ),
      imageAliases: parsed.aliases,
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
        _joinedChannels.add(channel);
        _addSystemMessage('Joining $channel', channel: channel);
        _addDebug('Current channel set to $_currentChannel');
        return true;
      case 'part':
        if (args.isEmpty) {
          _showError('Usage: /part <#channel>');
          return true;
        }
        final String channel = args.split(RegExp(r'\s+')).first;
        _sendRawLine('PART $channel');
        _joinedChannels.remove(channel);
        _addSystemMessage('Leaving $channel', channel: channel);
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
        if (!_channels.contains(target)) {
          setState(() {
            _channels.add(target);
          });
        }
        final ImageParseResult parsed = extractImageUrls(message);
        _addMessage(
          ChatMessage(
            id: _nextMessageId++,
            direction: MessageDirection.outgoing,
            kind: MessageKind.chat,
            text: message,
            imageUrls: parsed.urls,
            nick: _nickController.text.trim(),
            channel: target,
            timestamp: DateTime.now(),
          ),
          imageAliases: parsed.aliases,
        );
        return true;
      case 'list':
        _requestChannelList(auto: false);
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
          id: _nextMessageId++,
          direction: MessageDirection.outgoing,
          kind: MessageKind.raw,
          text: line,
          timestamp: DateTime.now(),
        ),
        channel: _statusChannel,
      );
    }
  }

  void _addMessage(
    ChatMessage message, {
    String? channel,
    Map<String, String>? imageAliases,
  }) {
    if (!mounted) {
      return;
    }
    final String targetChannel =
        channel ?? message.channel ?? _statusChannel;
    setState(() {
      final List<ChatMessage> bucket =
          _channelMessages.putIfAbsent(targetChannel, () => <ChatMessage>[]);
      bucket.add(message);
      if (imageAliases != null && imageAliases.isNotEmpty) {
        _imageUrlAliasesByMessageId[message.id] = imageAliases;
      }
    });
    _scrollToBottom();
  }

  void _addSystemMessage(String text, {String? channel}) {
    _addMessage(
      ChatMessage(
        id: _nextMessageId++,
        direction: MessageDirection.incoming,
        kind: MessageKind.system,
        text: text,
        timestamp: DateTime.now(),
      ),
      channel: channel ?? _statusChannel,
    );
  }

  void _addDebug(String line) {
    if (!_debugEnabled) {
      return;
    }
    final String timestamp = formatTimestamp(DateTime.now());
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
    final String displayText =
        _stripLoadedImageUrls(message.text, message.imageUrls, message.id);
    return MessageTile(
      message: message,
      displayText: displayText,
      onOpenImageViewer: _openImageViewer,
      onOpenUrlExternal: _openUrlExternal,
      onImageLoaded: (String url) => _markImageLoaded(message.id, url),
    );
  }

  void _markImageLoaded(int messageId, String url) {
    final Set<String> loaded =
        _loadedImageUrlsByMessageId.putIfAbsent(messageId, () => <String>{});
    if (loaded.contains(url)) {
      return;
    }
    setState(() {
      loaded.add(url);
      final Map<String, String>? aliases =
          _imageUrlAliasesByMessageId[messageId];
      if (aliases != null && aliases.containsKey(url)) {
        loaded.add(aliases[url]!);
      }
    });
  }

  String _stripLoadedImageUrls(
    String text,
    List<String> urls,
    int messageId,
  ) {
    if (urls.isEmpty) {
      return text;
    }
    final Set<String> loaded =
        _loadedImageUrlsByMessageId[messageId] ?? <String>{};
    if (loaded.isEmpty) {
      return text;
    }
    String result = text;
    for (final String url in urls) {
      if (loaded.contains(url)) {
        result = result.replaceAll(url, '');
      }
    }
    for (final String alias in loaded) {
      result = result.replaceAll(alias, '');
    }
    result = result.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return result;
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

  Future<void> _openUrlExternal(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      _showError('Invalid URL.');
      return;
    }
    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      _showError('Unable to open URL.');
    }
  }

  void _handleChannelSelected(String value) {
    setState(() {
      _currentChannel = value;
    });
    _scrollToBottom();
    if (value != _statusChannel && !_joinedChannels.contains(value)) {
      _sendRawLine('JOIN $value');
      _joinedChannels.add(value);
      _addSystemMessage('Joining $value', channel: value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isConnecting = _status == ConnectionStatus.connecting;
    final bool isConnected = _status == ConnectionStatus.connected;
    String activeChannel =
        _currentChannel.isEmpty ? _statusChannel : _currentChannel;
    final List<String> channelOptions = <String>[
      _statusChannel,
      ..._channels,
    ];
    if (!channelOptions.contains(activeChannel)) {
      activeChannel = _statusChannel;
    }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final LinearGradient backgroundGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const <Color>[
              Color(0xFF0B1220),
              Color(0xFF111827),
              Color(0xFF0F172A),
            ]
          : const <Color>[
              Color(0xFFF7FAFF),
              Color(0xFFF1F5FF),
              Color(0xFFF5F7FB),
            ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTabIndex == 0 ? 'Chat' : 'Connection'),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: SafeArea(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: _currentTabIndex == 0
                ? ChatPage(
                    isConnected: isConnected,
                    statusLabel: _statusLabel(),
                    statusColor: _statusColor(),
                    statusChannel: _statusChannel,
                    currentChannel: activeChannel,
                    channels: _channels,
                    visibleMessages:
                        _channelMessages[activeChannel] ?? <ChatMessage>[],
                    scrollController: _scrollController,
                    messageController: _messageController,
                    onChannelSelected: _handleChannelSelected,
                    onSendMessage: _sendMessage,
                    messageBuilder: _buildMessageTile,
                  )
                : SettingsPage(
                    isConnected: isConnected,
                    isConnecting: isConnecting,
                    ipController: _ipController,
                    portController: _portController,
                    nickController: _nickController,
                    userController: _userController,
                    realnameController: _realnameController,
                    fingerprintController: _fingerprintController,
                    useTls: _useTls,
                    tlsMode: _tlsMode,
                    debugEnabled: _debugEnabled,
                    debugLines: _debugLines,
                    showRawMessages: _showRawMessages,
                    autoConnect: _autoConnect,
                    themeMode: widget.themeMode,
                    onConnect: _connect,
                    onDisconnect: () => _disconnect(manual: true),
                    onUseTlsChanged: (bool value) {
                      setState(() {
                        _useTls = value;
                      });
                    },
                    onTlsModeChanged: (TlsMode? value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _tlsMode = value;
                      });
                    },
                    onDebugChanged: (bool value) {
                      setState(() {
                        _debugEnabled = value;
                      });
                    },
                    onShowRawMessagesChanged: (bool value) {
                      setState(() {
                        _showRawMessages = value;
                      });
                    },
                    onThemeModeChanged: (ThemeMode? value) {
                      if (value == null) {
                        return;
                      }
                      widget.onThemeModeChanged(value);
                    },
                    onAutoConnectChanged: (bool value) {
                      setState(() {
                        _autoConnect = value;
                      });
                    },
                  ),
          ),
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
}
