typedef LoadPresenceIds = Future<Iterable<String?>> Function();
typedef DeletePresenceById = Future<void> Function(String id);

Future<int> deleteAllPresenceDocuments({
  required LoadPresenceIds loadIds,
  required DeletePresenceById deleteById,
}) async {
  final ids = (await loadIds())
      .map((id) => id?.trim())
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet();
  for (final id in ids) {
    await deleteById(id);
  }
  return ids.length;
}
