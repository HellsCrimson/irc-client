String formatTimestamp(DateTime time) {
  final String hour = time.hour.toString().padLeft(2, '0');
  final String minute = time.minute.toString().padLeft(2, '0');
  final String second = time.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}
