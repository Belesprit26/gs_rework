/// Returns `true` if [current] >= [minimum] using simple semver comparison.
///
/// Both strings must be in the form "major.minor.patch".
bool isVersionSupported(String current, String minimum) {
  final cur = _parse(current);
  final min = _parse(minimum);

  for (var i = 0; i < 3; i++) {
    if (cur[i] > min[i]) return true;
    if (cur[i] < min[i]) return false;
  }
  return true; // equal
}

List<int> _parse(String v) {
  final parts = v.split('.');
  return List.generate(3, (i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0);
}
