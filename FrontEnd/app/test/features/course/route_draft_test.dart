import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/geo_point.dart';
import 'package:wadadak/features/course/create/route_draft.dart';

void main() {
  const cityHall = GeoPoint(37.5666, 126.9784);
  // 시청에서 북쪽으로 998.9m(PostGIS 값) — 반올림해도 1km가 안 된다.
  const north = GeoPoint(37.5756, 126.9784);
  const east = GeoPoint(37.5756, 126.9897);

  test('needs two points and 1 km to go on', () {
    var draft = const RouteDraft();
    expect(draft.canProceed, isFalse);

    draft = draft.add(cityHall);
    expect(draft.distanceMeters, 0);
    expect(draft.canProceed, isFalse);

    draft = draft.add(north);
    expect(draft.distanceMeters, closeTo(998.8953876001274, 0.001));
    expect(draft.canProceed, isFalse, reason: '998.9m는 반올림해도 999m');

    draft = draft.add(east);
    expect(draft.points, [cityHall, north, east]);
    expect(draft.distanceMeters, GeoPoint.pathLength(draft.points));
    expect(draft.canProceed, isTrue);
  });

  test('100 km is the longest drawn course', () {
    // 서울 시청 → 부산(약 325km)
    final draft = const RouteDraft().add(cityHall).add(const GeoPoint(35.1796, 129.0756));
    expect(draft.withinDistance, isFalse);
    expect(draft.canProceed, isFalse);
    // 서울 시청 → 천안(84.3km)
    expect(const RouteDraft().add(cityHall).add(const GeoPoint(36.8151, 127.1139)).canProceed, isTrue);
  });

  test('undo takes back the last edit, as far back as the first point', () {
    var draft = const RouteDraft().add(cityHall).add(north).add(east);

    draft = draft.undo();
    expect(draft.points, [cityHall, north]);
    expect(draft.distanceMeters, GeoPoint.pathLength([cityHall, north]));

    draft = draft.undo().undo();
    expect(draft.isEmpty, isTrue);
    expect(draft.canUndo, isFalse);
    expect(draft.undo(), same(draft));
  });

  test('clear all can be undone', () {
    final drawn = const RouteDraft().add(cityHall).add(north).add(east);

    final cleared = drawn.clear();
    expect(cleared.isEmpty, isTrue);
    expect(cleared.distanceMeters, 0);

    final restored = cleared.undo();
    expect(restored.points, drawn.points);
    expect(restored.distanceMeters, drawn.distanceMeters);
    // 지우기 전의 편집도 이어서 되돌릴 수 있다.
    expect(restored.undo().points, [cityHall, north]);

    // 점이 없으면 지울 것도, 되돌릴 기록도 생기지 않는다.
    expect(const RouteDraft().clear().canUndo, isFalse);
  });

  test('stops at 500 points', () {
    var draft = const RouteDraft();
    for (var i = 0; i < RouteDraft.maxPoints; i++) {
      draft = draft.add(GeoPoint(37.5 + i * 0.0001, 127));
    }
    expect(draft.points, hasLength(500));
    expect(draft.isFull, isTrue);
    expect(draft.add(cityHall), same(draft));
    expect(draft.undo().isFull, isFalse);
  });
}
