import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

void main() => runApp(const CatalogApp());

class CatalogApp extends StatelessWidget {
  const CatalogApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '와다닥 디자인 시스템',
        theme: WdTheme.light(),
        debugShowCheckedModeBanner: false,
        home: const CatalogPage(),
      );
}

/// Figma 공통 컴포넌트 섹션과 나란히 놓고 비교하기 위한 카탈로그. 값은 Figma 시안 그대로.
class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  int nav = 0, mode = 0, builder = 0, filter = 0, rating = 4;
  bool agreeAll = true, agreeTerms = false, toggle = true;
  final search = TextEditingController(text: '한강');

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Widget get route => SvgPicture.asset('assets/route.svg', fit: BoxFit.cover);

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: WdAppBar(
            title: '디자인 시스템',
            action: WdAppBarAction.circle(WdIcons.settings, semanticLabel: '설정', onTap: () {}),
          ),
          bottomNavigationBar: WdBottomNav(currentIndex: nav, onTap: (i) => setState(() => nav = i)),
          body: ListView(children: [
            _foundations(),
            _navigation(),
            _buttons(),
            _inputs(),
            _feedback(),
            _cards(),
            _running(),
            _map(),
            _analysis(),
          ]),
        ),
      );

  Widget _foundations() => _section('Foundations', [
        _pad(Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (name, color) in const [
            ('ink', WdColors.ink),
            ('dark', WdColors.dark),
            ('darkCard', WdColors.darkCard),
            ('muted', WdColors.muted),
            ('grayLight', WdColors.grayLight),
            ('line', WdColors.line),
            ('map', WdColors.map),
            ('soft', WdColors.soft),
            ('lime', WdColors.lime),
            ('limeSoft', WdColors.limeSoft),
            ('green', WdColors.green),
            ('recordSelf', WdColors.recordSelfSurface),
            ('info', WdColors.info),
            ('warning', WdColors.warning),
            ('success', WdColors.success),
          ])
            SizedBox(
              width: 64,
              child: Column(spacing: 4, children: [
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(WdRadius.r8),
                    border: Border.all(color: WdColors.line),
                  ),
                ),
                Text(name, style: WdText.micro10.copyWith(color: WdColors.muted)),
              ]),
            ),
        ])),
        for (final (name, style) in const [
          ('04 Metric / 20 Bold', WdText.metric20),
          ('07 Card title / 14 Bold', WdText.cardTitle14),
          ('08 Button / 15 Bold', WdText.button15),
          ('09 Body / 13 Regular', WdText.body13),
          ('12 Label / 12 Regular', WdText.label12),
          ('15 Caption / 11 Regular', WdText.caption11),
          ('A DS / Korean/16 Bold', WdText.ko16Bold),
          ('A DS / Numeric/24 Bold 27:14', WdText.numeric24),
        ])
          _pad(Text(name, style: style.copyWith(color: WdColors.ink))),
        _pad(const Row(spacing: 16, children: [WdLogo(), WdLogo(height: 24, symbolOnly: true)])),
        _pad(const Row(spacing: 12, children: [
          WdIcon(WdIcons.ghostInfo, size: 24),
          WdIcon(WdIcons.ghostWarning, size: 24),
          WdIcon(WdIcons.ghostSuccess, size: 24),
          WdIcon(WdIcons.back),
          WdIcon(WdIcons.share),
          WdIcon(WdIcons.sliders),
          WdIcon(WdIcons.settings),
          WdIcon(WdIcons.search),
        ])),
      ]);

  Widget _navigation() => _section('Navigation', [
        WdAppBar(title: '필터', onBack: () {}, action: WdAppBarAction.text('초기화', onTap: () {})),
        WdAppBar(title: '서비스 이용 동의', onBack: () {}, action: WdAppBarAction.circle(WdIcons.sliders, semanticLabel: '설정', onTap: () {})),
        WdAppBar(title: '한강 야경 5K', onBack: () {}, action: WdAppBarAction.icon(WdIcons.share, semanticLabel: '공유', onTap: () {})),
        WdAppBar(title: '필터', onBack: () {}, action: WdAppBarAction.button('저장', primary: true, onTap: () {})),
        WdAppBar(title: 'MY', large: true, action: WdAppBarAction.circle(WdIcons.sliders, semanticLabel: '설정', onTap: () {})),
        const WdTabBar(tabs: ['코스 정보', '리뷰']),
        _pad(WdSegmentedControl(
          items: const ['자유 러닝', '코스 러닝', '고스트 대결'],
          selectedIndex: mode,
          onChanged: (i) => setState(() => mode = i),
        )),
        _pad(WdSegmentedControl(
          style: WdSegmentStyle.light,
          items: const ['경로 그리기', '내가 달려서 등록'],
          selectedIndex: builder,
          onChanged: (i) => setState(() => builder = i),
        )),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(spacing: 8, children: [
            for (final (i, f) in const ['인기순', '가까운순', '난이도', '평점', '태그'].indexed)
              WdFilterChip(f, selected: filter == i, onTap: () => setState(() => filter = i)),
            WdFilterChip.icon(WdIcons.sliders, semanticLabel: '상세 필터', onTap: () {}),
          ]),
        ),
      ]);

  Widget _buttons() => _section('Buttons', [
        _pad(WdButton('러닝 시작', onPressed: () {})),
        _pad(WdButton('러닝 시작', variant: WdButtonVariant.secondary, onPressed: () {})),
        _pad(WdButton('다음', showArrow: true, onPressed: () {})),
        _pad(const WdButton('동의하고 계속하기', onPressed: null)),
        WdBottomBar.dual(
          secondary: WdButton('이 코스로 달리기', variant: WdButtonVariant.secondary, onPressed: () {}),
          primary: WdButton('고스트 대결 ▶', onPressed: () {}),
        ),
        for (final p in WdSocialProvider.values) _pad(WdSocialLoginButton(p, onPressed: () {})),
      ]);

  Widget _inputs() => _section('Inputs', [
        _pad(const WdTextField(hintText: '입력값')),
        WdSearchHeader(controller: search, onBack: () {}),
        _pad(const WdSearchBar()),
        _pad(WdConsentRow(
          label: '전체 동의하기',
          checked: agreeAll,
          onChanged: (v) => setState(() => agreeAll = v),
        )),
        _pad(WdConsentRow(
          label: '[필수] 서비스 이용약관',
          checked: agreeTerms,
          onChanged: (v) => setState(() => agreeTerms = v),
          onView: () {},
        )),
        _pad(Column(children: [
          const WdListRow(label: '항목'),
          WdListRow(label: '항목', value: '값', onTap: () {}),
          WdListRow(label: '항목', toggle: toggle, onToggle: (v) => setState(() => toggle = v)),
        ])),
        _pad(WdRatingRow(label: '안전성 (차량 · 인적)', value: rating, onChanged: (v) => setState(() => rating = v))),
        _pad(WdPhotoUpload(photos: const [], onAdd: () {})),
        _pad(Align(
          alignment: Alignment.centerLeft,
          child: WdStepper(value: '1.0 km', onDecrement: () {}, onIncrement: () {}),
        )),
      ]);

  Widget _feedback() => _section('Feedback', [
        for (final t in WdBannerTone.values) _pad(WdInfoBanner('안내 문구가 들어갑니다.', tone: t)),
        _pad(Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in WdTone.values) WdTag('태그', tone: t),
          const WdTag('완주 100%', tone: WdTone.success, filled: false),
          const WdTag('만료 D-7', tone: WdTone.warning, filled: false),
        ])),
        _pad(const WdProgressBar(value: 0.6)),
        _pad(const WdRemainingDistance(leading: '남은 거리 2.79 km', trailing: '3 km 지점까지 590 m', progress: 0.3)),
        _pad(const WdStepRow(title: '정보 입력 후 등록', description: '이름 · 난이도 · 특징 태그를 붙이면 공통 지도에 올라갑니다.')),
        const WdStateMessage(title: 'GPS 신호가 약해요', message: '정확도 ±38m\n위치가 정확해지면 코스 러닝을 시작할 수 있어요.'),
      ]);

  Widget _cards() => _section('Cards', [
        _pad(const WdSummaryTiles([('총 거리', '3.4km'), ('1 km 지점', '5')])),
        _pad(const WdStatSummary([('참여 러너', '312명'), ('1위 기록', '24:12'), ('평균 기록', '28:40')])),
        _pad(const WdMetric(label: '평균 페이스', value: '5′11″')),
        _pad(WdCourseCard(
          title: '한강 다리 왕복 8K',
          lines: const ['8.1km · 난이도 상 · ★ 4.4', '만든 사람 러너_하늘'],
          thumbnail: route,
          thumbnailSize: const Size(54, 54),
          tags: const [
            WdTag('만료 D-7', tone: WdTone.warning, filled: false),
          ],
          actionLabel: '이 코스로 달리기 ›',
          onAction: () {},
        )),
        _pad(WdCourseCard(
          title: '한강 야경 5K',
          lines: const ['5.2km · 난이도 중 · ★ 4.6 (128)'],
          thumbnail: route,
          showChevron: true,
          tags: const [
            WdTag('3명 달리는 중', tone: WdTone.success, filled: false),
            WdTag('달려서 만든 코스', filled: false),
          ],
          onTap: () {},
        )),
        _pad(WdRunRecordCard(
          title: '한강 야경 5K',
          summary: '5.21km · 27:14 · 5′14″/km',
          date: '09.08 (월)',
          resultTag: const WdTag('대결 승', tone: WdTone.success, filled: false),
          thumbnail: route,
          onTap: () {},
        )),
        _pad(WdRunRecordCard.selectable(
          title: '09.03 (수)',
          summary: '4.10 km · 22:40 · 5′32″/km',
          thumbnail: route,
          tags: const [
            WdTag('코스 러닝, 자유 러닝', filled: false),
            WdTag('등록 가능', tone: WdTone.success, filled: false),
          ],
          onTap: () {},
        )),
        _pad(const WdReviewCard(
          author: '러너_하늘',
          badge: '완주 100%',
          meta: '2026.09.06 · 4회 주행',
          rating: 5,
          body: '야간 조명이 밝아서 혼자 뛰어도 안전합니다. 다리 구간 바람이 좀 셉니다.',
          tags: ['야경 좋음', '신호 적음'],
        )),
        _pad(WdSelectedCourseCard(
          title: '한강 야경 5K',
          meta: '5.2 km · 난이도 중 · 평지',
          status: '★ 4.6  ·  지금 3명 달리는 중',
          thumbnail: route,
          onChange: () {},
        )),
        _pad(WdSectionHeading('전체 순위 312명', actionLabel: '러너를 탭하면 프로필 ›', onAction: () {})),
        _pad(const WdMyRankCard(WdRank(rank: '24', name: '나 (wonehgus)', meta: '5′14″/km · 09.08 · 상위 8%', value: '27:14'))),
        _pad(const WdRankList(ranks: [
          WdRank(rank: '1', name: '러너_하늘', meta: '4′39″/km · 09.07', value: '24:12'),
          WdRank(rank: '2', name: '러너_민', meta: '4′46″/km · 08.30', value: '24:48'),
          WdRank(rank: '3', name: '성북러너', meta: '4′49″/km · 09.01', value: '25:02'),
        ])),
        _pad(WdMenuCard(items: [
          WdMenuItem(label: '내 러닝 기록', value: '42회', onTap: () {}),
          WdMenuItem(label: '내가 등록한 코스', value: '5개', onTap: () {}),
          WdMenuItem(label: '저장한 코스', value: '12개', onTap: () {}),
        ])),
      ]);

  Widget _running() => _section('Running (dark)', dark: true, [
        const WdRunHeader(title: '한강 야경 5K', subtitle: '코스 러닝'),
        const WdElapsedTime(time: '12:34', caption: '총 소요 13:02'),
        _pad(const Row(spacing: 16, children: [
          Expanded(child: WdRunMetricTile(label: '거리', value: '2.41 km')),
          Expanded(child: WdRunMetricTile(label: '평균 페이스', value: '5′13″')),
        ])),
        _pad(const Row(spacing: 16, children: [
          Expanded(child: WdMetric(label: '평균 페이스', value: '5′11″', dark: true)),
          Expanded(child: WdMetric(label: '심박수', value: '124 bpm', dark: true)),
        ])),
        _pad(const WdGhostLeadCard(
          title: '고스트보다 앞서고 있어요',
          value: '+12 m',
          caption: '약 4초 앞서는 중',
          message: '지금 페이스를 이어가세요.',
        )),
        _pad(const WdLapRecords(laps: [
          WdLap(label: '1 km', pace: '5′18″', delta: '6초 느림'),
          WdLap(label: '2 km', pace: '5′08″', delta: '8초 빠름', faster: true),
          WdLap(label: '현재 0.41 km', pace: '5′14″', delta: '2초 빠름', faster: true, current: true),
        ])),
        _pad(const WdCourseProgress(
          progress: 0.46,
          ghostProgress: 0.432,
          leading: '3 km 지점까지 590 m',
          trailing: '총 5.2 km',
        )),
        _pad(const WdRemainingDistance(leading: '남은 거리 2.79 km', trailing: '코스 진행 46%', progress: 0.3, dark: true)),
        const Center(child: WdPageIndicator(count: 3, index: 1)),
        _pad(WdRunPauseButton(onPressed: () {})),
        _pad(WdRunPausedButtons(onStop: () {}, onResume: () {})),
        _pad(const WdSensorStatus([('GPS 신호', '좋음 (±4m)'), ('케이던스 센서', '연결됨')])),
        _pad(WdRecordCard(
          overline: '코스 최고 기록',
          title: '이 코스의 내 최고 기록',
          time: '27:14',
          caption: '평균 페이스 5′14″',
          footer: '코스 순위 24위 / 312명  ·  목표 26:40 (−34초)',
          onTap: () {},
        )),
      ]);

  Widget _map() => _section('Map', [
        Container(
          color: WdColors.map,
          padding: const EdgeInsets.all(24),
          child: Column(spacing: 16, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(spacing: 16, children: [
              WdMapLocateButton(onPressed: () {}),
              WdMapZoomControl(onZoomIn: () {}, onZoomOut: () {}),
              const WdKmMarker('1 km'),
              const WdRoutePoint(),
              const WdRegionCountBubble(count: '1,240', region: '서울'),
            ]),
            const WdSheetPeek(title: '↑ 위로 올려 코스 목록 보기', meta: ' 전국 3,412'),
          ]),
        ),
      ]);

  Widget _analysis() => _section('Analysis', [
        _pad(const WdSegmentChart(
          title: '구간별 페이스 (1km 단위)',
          values: [0.548, 0.833, 0.429, 1, 0.655],
          labels: ['1 km', '2 km', '3 km', '4 km', '5 km'],
          maxLabel: '5′02″',
          minLabel: '5′22″',
          highlightIndex: 3,
          reference: [0.714, 0.595, 0.345, 0.69, 0.595],
        )),
        _pad(const WdSegmentChart(
          title: '구간별 케이던스 (1km 단위)',
          values: [0.429, 0.679, 0.548, 1, 0.714],
          labels: ['1 km', '2 km', '3 km', '4 km', '5 km'],
          maxLabel: '186',
          minLabel: '172',
          highlightIndex: 3,
          reference: [0.595],
          legend: ('나', '평균 케이던스'),
        )),
        _pad(const WdSegmentChart(
          title: '구간별 고도 변화 (1km 단위)',
          values: [0.655, 0.798, 1, 0, 0.5],
          baseline: 0.2024,
          labels: ['1 km', '2 km', '3 km', '4 km', '5 km'],
          maxLabel: '+32 m',
          minLabel: '−8 m',
          highlightIndex: 2,
          reference: [0.2024],
          legend: ('고도 변화', '시작 고도'),
        )),
        _pad(const WdSegmentTable(rows: [
          WdSegmentRow('1 km', '5′18″', '172', '6초 느림', faster: false),
          WdSegmentRow('2 km', '5′08″', '178', '8초 빠름'),
          WdSegmentRow('3 km', '5′22″', '175', '3초 빠름'),
        ])),
      ]);

  static Widget _pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: child);

  static Widget _section(String title, List<Widget> children, {bool dark = false}) => ColoredBox(
        color: dark ? WdColors.dark : WdColors.paper,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              _pad(Text(title, style: WdText.metric20.copyWith(color: dark ? WdColors.white : WdColors.ink))),
              ...children,
            ],
          ),
        ),
      );
}
