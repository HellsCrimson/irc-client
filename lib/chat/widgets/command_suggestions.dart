import 'package:flutter/material.dart';

class CommandSuggestions extends StatelessWidget {
  const CommandSuggestions({
    super.key,
    required this.messageController,
    required this.commandSuggestions,
    required this.focusNode,
  });

  final TextEditingController messageController;
  final List<String> commandSuggestions;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: messageController,
      builder: (BuildContext context, TextEditingValue value, _) {
        final String text = value.text;
        final bool showSuggestions = text.startsWith('/') && text.length <= 20;
        if (!showSuggestions) {
          return const SizedBox.shrink();
        }
        final String query = text.length > 1 ? text.substring(1).toLowerCase() : '';
        final List<String> suggestions = commandSuggestions
            .where((String cmd) => cmd.substring(1).startsWith(query))
            .toList();
        if (suggestions.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withOpacity(0.9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: suggestions.map((String cmd) {
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    messageController.text = '$cmd ';
                    messageController.selection = TextSelection.collapsed(
                      offset: messageController.text.length,
                    );
                    focusNode.requestFocus();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      cmd,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}
