String displaySpeakerLabel(String? value, {String fallback = '화자 1'}) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return fallback;

  final match = RegExp(
    r'^spk_(\d+)(?:\s*\((.+)\))?$',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (match == null) return normalized;

  final index = int.tryParse(match.group(1) ?? '');
  if (index == null) return normalized;

  final participant = '참가자 ${index + 1}';
  final suffix = match.group(2)?.trim();
  return suffix == null || suffix.isEmpty
      ? participant
      : '$participant ($suffix)';
}
