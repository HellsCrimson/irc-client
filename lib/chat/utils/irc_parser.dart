import '../models.dart';

IrcLine? parseIrcLine(String line) {
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

bool isChannel(String target) {
  return target.startsWith('#') || target.startsWith('&');
}
