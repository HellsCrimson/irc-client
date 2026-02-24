import 'package:flutter/material.dart';

Color colorForNick(String nick) {
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
