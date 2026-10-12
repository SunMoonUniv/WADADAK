import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 위도·경도(WGS84). 서버 `common.geo.GeoPoint`와 같다. API는 `{"lat": .., "lng": ..}`로 주고받는다.
@immutable
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  factory GeoPoint.fromJson(Map<Object?, Object?> json) =>
      GeoPoint((json['lat']! as num).toDouble(), (json['lng']! as num).toDouble());

  final double lat;
  final double lng;

  Map<String, Object?> toJson() => {'lat': lat, 'lng': lng};

  /// 이 점까지 WGS84 타원체 위의 거리(m). 서버가 경로 거리를 재는 기준(PostGIS `ST_Length(geography)`)과 같다.
  ///
  /// Vincenty 역해법. 거의 정반대편인 두 점이 아니면 1mm 안쪽으로 맞는다.
  double distanceTo(GeoPoint other) {
    const a = 6378137.0;
    const f = 1 / 298.257223563;
    const b = a * (1 - f);
    const rad = math.pi / 180;

    final l = (other.lng - lng) * rad;
    final u1 = math.atan((1 - f) * math.tan(lat * rad));
    final u2 = math.atan((1 - f) * math.tan(other.lat * rad));
    final sinU1 = math.sin(u1), cosU1 = math.cos(u1);
    final sinU2 = math.sin(u2), cosU2 = math.cos(u2);

    var lambda = l;
    var sinSigma = 0.0, cosSigma = 0.0, sigma = 0.0, cos2Alpha = 0.0, cos2SigmaM = 0.0;
    for (var i = 0; i < 100; i++) {
      final sinLambda = math.sin(lambda), cosLambda = math.cos(lambda);
      final x = cosU2 * sinLambda;
      final y = cosU1 * sinU2 - sinU1 * cosU2 * cosLambda;
      sinSigma = math.sqrt(x * x + y * y);
      if (sinSigma == 0) return 0; // 같은 점
      cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda;
      sigma = math.atan2(sinSigma, cosSigma);
      final sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma;
      cos2Alpha = 1 - sinAlpha * sinAlpha;
      // 적도 위의 선이면 cos2Alpha가 0이다.
      cos2SigmaM = cos2Alpha == 0 ? 0 : cosSigma - 2 * sinU1 * sinU2 / cos2Alpha;
      final c = f / 16 * cos2Alpha * (4 + f * (4 - 3 * cos2Alpha));
      final previous = lambda;
      lambda = l +
          (1 - c) *
              f *
              sinAlpha *
              (sigma + c * sinSigma * (cos2SigmaM + c * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)));
      if ((lambda - previous).abs() < 1e-12) break;
    }

    final uSq = cos2Alpha * (a * a - b * b) / (b * b);
    final bigA = 1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)));
    final bigB = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)));
    final deltaSigma = bigB *
        sinSigma *
        (cos2SigmaM +
            bigB /
                4 *
                (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM) -
                    bigB / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) * (-3 + 4 * cos2SigmaM * cos2SigmaM)));
    return b * bigA * (sigma - deltaSigma);
  }

  /// [points]를 순서대로 직선으로 이은 길이(m).
  static double pathLength(List<GeoPoint> points) {
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += points[i - 1].distanceTo(points[i]);
    }
    return length;
  }

  @override
  bool operator ==(Object other) => other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'GeoPoint($lat, $lng)';
}
