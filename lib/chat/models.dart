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
    required this.id,
    required this.direction,
    required this.kind,
    required this.text,
    required this.timestamp,
    this.nick,
    this.channel,
    this.imageUrls = const <String>[],
  });

  final int id;
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

class ImageParseResult {
  const ImageParseResult({
    required this.urls,
    required this.aliases,
  });

  final List<String> urls;
  final Map<String, String> aliases;
}
