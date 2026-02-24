import '../models.dart';

ImageParseResult extractImageUrls(String text) {
  final RegExp urlRegex = RegExp(
    r'(https?:\/\/[^\s]+)',
    caseSensitive: false,
  );
  final List<String> urls = <String>[];
  final Map<String, String> aliases = <String, String>{};

  for (final RegExpMatch match in urlRegex.allMatches(text)) {
    final String? raw = match.group(1);
    if (raw == null) {
      continue;
    }
    final String? resolved = resolveImageUrl(raw);
    if (resolved == null) {
      continue;
    }
    urls.add(resolved);
    if (resolved != raw) {
      aliases[resolved] = raw;
    }
  }

  return ImageParseResult(urls: urls, aliases: aliases);
}

String? resolveImageUrl(String url) {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null) {
    return null;
  }
  final String lowerPath = uri.path.toLowerCase();
  final bool isImageExtension = lowerPath.endsWith('.png') ||
      lowerPath.endsWith('.jpg') ||
      lowerPath.endsWith('.jpeg') ||
      lowerPath.endsWith('.gif') ||
      lowerPath.endsWith('.webp');
  if (isImageExtension) {
    return url;
  }
  if (lowerPath.endsWith('.gifv')) {
    return url.replaceFirst('.gifv', '.gif');
  }
  if (uri.host.contains('giphy.com')) {
    if (lowerPath.contains('/media/') && lowerPath.endsWith('/giphy.gif')) {
      return url;
    }
    if (uri.pathSegments.isNotEmpty) {
      String id = uri.pathSegments.last;
      if (id.contains('-')) {
        id = id.split('-').last;
      }
      if (id.isNotEmpty) {
        return 'https://media.giphy.com/media/$id/giphy.gif';
      }
    }
  }
  if (uri.host.contains('tenor.com')) {
    if (uri.host.startsWith('media.tenor.com') &&
        lowerPath.endsWith('.gif')) {
      return url;
    }
    if (uri.pathSegments.isNotEmpty) {
      final String last = uri.pathSegments.last;
      final String id = last.contains('-') ? last.split('-').last : last;
      if (id.isNotEmpty) {
        return 'https://media.tenor.com/$id/tenor.gif';
      }
    }
  }
  if (uri.host.contains('discordapp.com') ||
      uri.host.contains('discord.com') ||
      uri.host.contains('discordapp.net')) {
    if (isImageExtension) {
      return url;
    }
  }
  return null;
}
