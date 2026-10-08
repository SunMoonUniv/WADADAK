/// 활동 지역(시·군·구)과 법정동 코드.
class Region {
  const Region(this.name, this.code);

  final String name;

  /// 법정동 코드 10자리.
  final String code;
}

/// ponytail: 임시 목록. 지역 데이터와 지역 목록 API(F1 담당)가 생기면 서버 목록으로 바꾼다.
const kRegions = [
  Region('서울 강남구', '1168000000'),
  Region('서울 마포구', '1144000000'),
  Region('서울 성북구', '1129000000'),
  Region('충남 아산시', '4420000000'),
  Region('충남 천안시 동남구', '4413100000'),
  Region('충남 천안시 서북구', '4413300000'),
];
