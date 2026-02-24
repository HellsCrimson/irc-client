import 'package:flutter/material.dart';

import '../models.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({
    super.key,
    required this.isConnected,
    required this.statusLabel,
    required this.statusColor,
    required this.statusChannel,
    required this.currentChannel,
    required this.channels,
    required this.visibleMessages,
    required this.scrollController,
    required this.messageController,
    required this.onChannelSelected,
    required this.onSendMessage,
    required this.messageBuilder,
  });

  final bool isConnected;
  final String statusLabel;
  final Color statusColor;
  final String statusChannel;
  final String currentChannel;
  final List<String> channels;
  final List<ChatMessage> visibleMessages;
  final ScrollController scrollController;
  final TextEditingController messageController;
  final ValueChanged<String> onChannelSelected;
  final VoidCallback onSendMessage;
  final Widget Function(ChatMessage message) messageBuilder;

  @override
  Widget build(BuildContext context) {
    String activeChannel =
        currentChannel.isEmpty ? statusChannel : currentChannel;
    final List<String> channelOptions = <String>[
      statusChannel,
      ...channels,
    ];
    if (!channelOptions.contains(activeChannel)) {
      activeChannel = statusChannel;
    }

    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Row(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(statusLabel),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Row(
            children: <Widget>[
              const Text('Channel:'),
              const SizedBox(width: 8),
              if (channels.isEmpty) const Text('Status'),
              if (channels.isNotEmpty)
                Expanded(
                  child: DropdownButton<String>(
                    value: activeChannel,
                    isExpanded: true,
                    onChanged: (String? value) {
                      if (value == null) {
                        return;
                      }
                      onChannelSelected(value);
                    },
                    items: channelOptions
                        .map(
                          (String channel) => DropdownMenuItem<String>(
                            value: channel,
                            child: Text(
                              channel == statusChannel ? 'Status' : channel,
                            ),
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
          child: visibleMessages.isEmpty
              ? const Center(child: Text('No messages yet.'))
              : ListView.builder(
                  controller: scrollController,
                  itemCount: visibleMessages.length,
                  itemBuilder: (BuildContext context, int index) {
                    return messageBuilder(visibleMessages[index]);
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
                  controller: messageController,
                  decoration: const InputDecoration(
                    labelText: 'Message (or /nick, /join, /part, /user, /msg)',
                    border: OutlineInputBorder(),
                  ),
                  enabled: isConnected,
                  onSubmitted: (_) => onSendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: isConnected ? onSendMessage : null,
                child: const Text('Send'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
