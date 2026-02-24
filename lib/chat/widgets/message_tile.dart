import 'package:flutter/material.dart';

import '../models.dart';
import '../utils/nick_color.dart';
import '../utils/time_utils.dart';

class MessageTile extends StatelessWidget {
  const MessageTile({
    super.key,
    required this.message,
    required this.displayText,
    required this.onOpenImageViewer,
    required this.onOpenUrlExternal,
    required this.onImageLoaded,
  });

  final ChatMessage message;
  final String displayText;
  final ValueChanged<String> onOpenImageViewer;
  final ValueChanged<String> onOpenUrlExternal;
  final ValueChanged<String> onImageLoaded;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (message.kind == MessageKind.system) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
          color: scheme.surfaceContainerHighest,
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
        color: scheme.surfaceContainerHigh,
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
    final Color bubbleColor =
        isOutgoing ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final Color textColor =
        isOutgoing ? scheme.onPrimaryContainer : scheme.onSurface;
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
                  formatTimestamp(message.timestamp),
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
                      color: colorForNick(message.nick!),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                if (isOutgoing)
                  Text(
                    message.nick == null || message.nick!.isEmpty
                        ? 'Me:'
                        : 'Me (${message.nick}):',
                    style: TextStyle(
                      color: textColor.withOpacity(0.7),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              displayText,
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
                      onTap: () => onOpenImageViewer(url),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        loadingBuilder: (BuildContext context, Widget child,
                            ImageChunkEvent? loadingProgress) {
                          if (loadingProgress == null) {
                            onImageLoaded(url);
                            return child;
                          }
                          return child;
                        },
                        errorBuilder: (BuildContext context, Object error,
                            StackTrace? stackTrace) {
                          return Container(
                            color: const Color(0xFFE2E8F0),
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Text('Image failed to load.'),
                                const SizedBox(height: 6),
                                TextButton(
                                  onPressed: () => onOpenUrlExternal(url),
                                  child: const Text('Open in browser'),
                                ),
                              ],
                            ),
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
}
