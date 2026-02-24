import 'package:flutter/material.dart';

import '../models.dart';
import '../utils/time_utils.dart';

class ServerOutputPage extends StatelessWidget {
  const ServerOutputPage({
    super.key,
    required this.entries,
  });

  final List<ServerOutputEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('No server output yet.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: entries.length,
      itemBuilder: (BuildContext context, int index) {
        final ServerOutputEntry entry = entries[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                formatTimestamp(entry.timestamp),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                entry.text,
                style: const TextStyle(fontSize: 14.5, height: 1.35),
              ),
            ],
          ),
        );
      },
    );
  }
}
