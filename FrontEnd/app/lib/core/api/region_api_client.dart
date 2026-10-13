import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

const _provinces = {
  '서울특별시': '서울',
  '부산광역시': '부산',
  '대구광역시': '대구',
  '인천광역시': '인천',
  '대전광역시': '대전',
  '울산광역시': '울산',
  '세종특별자치시': '세종',
  '경기도': '경기',
  '강원특별자치도': '강원',
  '충청북도': '충북',
  '충청남도': '충남',
  '전북특별자치도': '전북',
  '경상북도': '경북',
  '경상남도': '경남',
  '제주특별자치도': '제주',
};

/// 시·군·구. 코드가 같으면 같은 지역이다.
class Region {
  const Region({required this.code, required this.name, required this.fullName});

  Region.fromJson(Map json)
      : code = json['code'] as String,
        name = json['name'] as String,
        fullName = json['fullName'] as String;

  /// 법정동 코드 10자리.
  final String code;

  /// 예: 천안시 동남구
  final String name;

  /// 상위 구역을 붙인 이름. 예: 충청남도 천안시 동남구
  final String fullName;

  /// 시·도 줄임 이름. 예: 충청남도 천안시 동남구 → 충남. 줄임 이름이 없으면 시·도 이름 그대로.
  String get province {
    final name = fullName.split(' ').first;
    return _provinces[name] ?? name;
  }

  @override
  bool operator ==(Object other) => other is Region && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// 지역 API(`/api/v1/regions`). 로그인 없이 쓴다(가입 화면에서도 부른다).
class RegionApiClient {
  RegionApiClient(this._publicDio);

  final Dio _publicDio;

  /// 이름에 [query]가 들어간 시·군·구, 최대 20개.
  Future<List<Region>> search(String query) async => [
        for (final region in await callApi(() => _publicDio.get('/api/v1/regions', queryParameters: {'query': query}))
            as List)
          Region.fromJson(region as Map),
      ];
}

final regionApiClientProvider = Provider<RegionApiClient>((ref) => RegionApiClient(ref.watch(publicDioProvider)));
