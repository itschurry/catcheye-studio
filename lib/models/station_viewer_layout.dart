enum StationViewerLayout {
  oneByOne('1×1', 1, 1),
  oneByTwo('1×2', 1, 2),
  twoByTwo('2×2', 2, 2);

  const StationViewerLayout(this.label, this.rows, this.columns);

  final String label;
  final int rows;
  final int columns;

  int get slotCount => rows * columns;

  static StationViewerLayout fromName(String? name) {
    return StationViewerLayout.values.firstWhere(
      (layout) => layout.name == name,
      orElse: () => StationViewerLayout.oneByOne,
    );
  }

  static StationViewerLayout forCameraCount(int count) {
    if (count <= 1) return StationViewerLayout.oneByOne;
    if (count <= 2) return StationViewerLayout.oneByTwo;
    return StationViewerLayout.twoByTwo;
  }

  StationViewerLayout accommodate(int cameraCount) {
    return slotCount >= cameraCount
        ? this
        : StationViewerLayout.forCameraCount(cameraCount);
  }
}

List<String> resizeStationCameraSlots(
  StationViewerLayout layout,
  Iterable<String> cameraIds,
) {
  final values = cameraIds.toList(growable: false);
  return List<String>.generate(
    layout.slotCount,
    (index) => index < values.length ? values[index] : '',
    growable: false,
  );
}

/// Keeps active cameras in their preferred slots and only uses empty slots for
/// cameras that were added by the runtime.
List<String> reconcileStationCameraSlots({
  required StationViewerLayout layout,
  required Iterable<String> preferredSlots,
  required Iterable<String> activeCameraIds,
}) {
  final active = activeCameraIds
      .map((cameraId) => cameraId.trim())
      .where((cameraId) => cameraId.isNotEmpty)
      .toSet();
  final slots = List<String>.filled(layout.slotCount, '');
  final placed = <String>{};
  final preferred = preferredSlots.toList(growable: false);

  for (
    var index = 0;
    index < slots.length && index < preferred.length;
    index++
  ) {
    final cameraId = preferred[index].trim();
    if (active.contains(cameraId) && placed.add(cameraId)) {
      slots[index] = cameraId;
    }
  }

  for (final cameraId in active) {
    if (!placed.add(cameraId)) continue;
    final emptySlot = slots.indexOf('');
    if (emptySlot < 0) break;
    slots[emptySlot] = cameraId;
  }
  return List.unmodifiable(slots);
}
