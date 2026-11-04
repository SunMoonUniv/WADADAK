import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../domain/run_models.dart';
import 'free_run_live_view.dart';

/// 러닝 결과 공유(Figma 없음 · MVP). 사진 위에 기록 스티커를 얹거나, 사진 없이 결과 이미지만 만든다.
Future<void> showRunShare(BuildContext context, RunSnapshot run) async {
  // 사진 출처, 사진 없이 결과 이미지만이면 null
  final pick = await showModalBottomSheet<(ImageSource?,)>(
    context: context,
    backgroundColor: WdColors.paper,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, icon, value) in [
            ('앨범 사진에 기록 얹기', Icons.photo_library_outlined, ImageSource.gallery),
            ('사진 찍어 기록 얹기', Icons.photo_camera_outlined, ImageSource.camera),
            ('결과 이미지만', Icons.image_outlined, null),
          ])
            ListTile(
              leading: Icon(icon, color: WdColors.ink),
              title: Text(label, style: WdText.ko16Bold),
              onTap: () => Navigator.pop(context, (value,)),
            ),
        ],
      ),
    ),
  );
  if (pick == null || !context.mounted) return;
  Uint8List? photo;
  if (pick.$1 case final source?) {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2160,
      maxHeight: 2160,
      requestFullMetadata: false,
    );
    if (picked == null) return;
    photo = await picked.readAsBytes();
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RunShareScreen(run: run, photo: photo),
    ),
  );
}

/// 처음 놓이는 자리(캔버스 비율)는 서로 겹치지 않게 위에서 아래로 둔다
enum RunSticker {
  course('코스 이름', Offset(.5, .1)),
  region('지역 이름', Offset(.5, .2)),
  route('경로', Offset(.5, .42)),
  distance('거리', Offset(.5, .7)),
  stats('기록', Offset(.5, .88));

  const RunSticker(this.label, this.home);
  final String label;
  final Offset home;
}

enum ShareRatio {
  square('1:1', 1),
  portrait('4:5', 4 / 5),
  story('9:16', 9 / 16);

  const ShareRatio(this.label, this.value);
  final String label;
  final double value;
}

/// 스티커는 캔버스 너비 360 기준으로 그리고 캔버스 크기에 맞춰 키운다. 위치는 캔버스 비율(0~1)이라 비율을 바꿔도 따라간다.
class RunShareScreen extends StatefulWidget {
  const RunShareScreen({
    super.key,
    required this.run,
    this.photo,
    this.region = lookupRegion,
    this.share = sharePng,
  });

  final RunSnapshot run;
  final Uint8List? photo;
  final Future<String?> Function(RunPoint start) region;
  final Future<void> Function(Uint8List png) share;

  @override
  State<RunShareScreen> createState() => _RunShareScreenState();
}

class _Placement {
  _Placement(this.at);
  Offset at;
  double scale = 1;
}

class _RunShareScreenState extends State<RunShareScreen> {
  final _canvas = GlobalKey();
  late var _ratio = widget.photo == null
      ? ShareRatio.square
      : ShareRatio.portrait;
  late final Map<RunSticker, _Placement> _placed = {
    for (final sticker
        in widget.photo == null
            ? [
                if (_course != null) RunSticker.course,
                if (_hasRoute) RunSticker.route,
                RunSticker.distance,
                RunSticker.stats,
              ]
            : [RunSticker.stats])
      sticker: _Placement(sticker.home),
  };
  String? _region;
  double _baseScale = 1;
  bool _sharing = false;

  String? get _course => widget.run.course?.courseName;
  bool get _hasRoute => widget.run.segments.any((s) => s.length > 1);

  List<RunSticker> get _available => [
    RunSticker.stats,
    RunSticker.distance,
    if (_hasRoute) RunSticker.route,
    if (_course != null) RunSticker.course,
    if (_region != null) RunSticker.region,
  ];

  @override
  void initState() {
    super.initState();
    final start = widget.run.segments
        .firstWhere((s) => s.isNotEmpty, orElse: () => const [])
        .firstOrNull;
    if (start != null) {
      widget.region(start).then((name) {
        if (mounted && name != null) setState(() => _region = name);
      });
    }
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _canvas.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(
        pixelRatio: 1080 / boundary.size.width,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await widget.share(data!.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WdColors.paper,
    appBar: WdAppBar(
      title: widget.photo == null ? '결과 이미지' : '사진 편집',
      onBack: () => Navigator.pop(context),
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: WdSegmentedControl(
              items: [for (final r in ShareRatio.values) r.label],
              selectedIndex: _ratio.index,
              onChanged: (i) => setState(() => _ratio = ShareRatio.values[i]),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Center(
                child: AspectRatio(
                  aspectRatio: _ratio.value,
                  child: RepaintBoundary(key: _canvas, child: _board()),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              spacing: 8,
              children: [
                for (final sticker in _available)
                  WdSurface(
                    key: ValueKey('chip-${sticker.name}'),
                    color: _placed.containsKey(sticker)
                        ? WdColors.lime
                        : WdColors.soft,
                    radius: WdRadius.full,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    onTap: () => setState(
                      () => _placed.containsKey(sticker)
                          ? _placed.remove(sticker)
                          : _placed[sticker] = _Placement(sticker.home),
                    ),
                    child: Text(sticker.label, style: WdText.ko13Medium),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              '끌어서 옮기고, 두 손가락으로 크기를 바꿔요',
              style: WdText.ko12.copyWith(color: WdColors.muted),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: WdButton('공유하기', onPressed: _sharing ? null : _share),
          ),
        ],
      ),
    ),
  );

  Widget _board() => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      final fit = size.width / 360;
      return ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: widget.photo == null
                  ? const ColoredBox(color: WdColors.ink)
                  : Image.memory(widget.photo!, fit: BoxFit.cover),
            ),
            for (final MapEntry(key: sticker, value: place) in _placed.entries)
              Positioned(
                left: place.at.dx * size.width,
                top: place.at.dy * size.height,
                child: FractionalTranslation(
                  translation: const Offset(-.5, -.5),
                  child: Transform.scale(
                    scale: place.scale * fit,
                    child: GestureDetector(
                      key: ValueKey('sticker-${sticker.name}'),
                      onScaleStart: (_) => _baseScale = place.scale,
                      onScaleUpdate: (d) => setState(() {
                        place.scale = (_baseScale * d.scale).clamp(.4, 3);
                        place.at = Offset(
                          (place.at.dx + d.focalPointDelta.dx / size.width)
                              .clamp(0, 1),
                          (place.at.dy + d.focalPointDelta.dy / size.height)
                              .clamp(0, 1),
                        );
                      }),
                      child: _sticker(sticker),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  static const _shadow = [Shadow(color: Color(0x66000000), blurRadius: 8)];

  Widget _sticker(RunSticker sticker) {
    final run = widget.run;
    final white = WdColors.white;
    return switch (sticker) {
      RunSticker.stats => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 20,
        children: [
          for (final (label, value) in [
            ('달린 시간', formatRunTime(run.active)),
            ('거리', runDistance(run)),
            ('평균 페이스', formatRunPace(run.paceSecondsPerKm)),
          ])
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: WdText.ko12Medium.copyWith(
                    color: white,
                    shadows: _shadow,
                  ),
                ),
                Text(
                  value,
                  style: WdText.ko22Bold.copyWith(
                    color: white,
                    shadows: _shadow,
                  ),
                ),
              ],
            ),
        ],
      ),
      RunSticker.distance => Text(
        runDistance(run),
        style: WdText.run56W800H74.copyWith(
          color: WdColors.lime,
          shadows: _shadow,
        ),
      ),
      RunSticker.route => CustomPaint(
        size: const Size.square(220),
        painter: _RoutePainter(run.segments),
      ),
      RunSticker.course => WdSurface(
        color: WdColors.lime,
        radius: WdRadius.full,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(_course ?? '', style: WdText.ko16Bold),
      ),
      RunSticker.region => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Icon(Icons.place, color: white, size: 20, shadows: _shadow),
          Text(
            _region ?? '',
            style: WdText.ko16Bold.copyWith(color: white, shadows: _shadow),
          ),
        ],
      ),
    };
  }
}

/// 달린 경로를 지도 없이 선으로만 그린다. 끊긴 구간은 잇지 않는다
class _RoutePainter extends CustomPainter {
  _RoutePainter(this.segments);
  final List<List<RunPoint>> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final points = segments.expand((s) => s).toList();
    if (points.length < 2) return;
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    // 위도마다 경도 1도 길이가 달라 cos(위도)를 곱해 평면에 가깝게 맞춘다
    final k = math.cos(points.first.latitude * math.pi / 180);
    Offset flat(RunPoint p) => Offset(p.longitude * k, -p.latitude);
    for (final p in points.map(flat)) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final span = math.max(math.max(maxX - minX, maxY - minY), 1e-9);
    final scale = (size.shortestSide - 16) / span;
    final offset = Offset(
      (size.width - (maxX - minX) * scale) / 2,
      (size.height - (maxY - minY) * scale) / 2,
    );
    Offset at(RunPoint p) => (flat(p) - Offset(minX, minY)) * scale + offset;
    final paint = Paint()
      ..color = WdColors.white
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final segment in segments.where((s) => s.length > 1)) {
      canvas.drawPath(
        Path()..addPolygon([for (final p in segment) at(p)], false),
        paint,
      );
    }
    canvas.drawCircle(at(points.first), 7, Paint()..color = WdColors.lime);
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.segments != segments;
}

/// 시작 지점의 "경기도 광명시" 같은 지역 이름. 못 찾으면 null(지역 이름 스티커를 숨긴다)
Future<String?> lookupRegion(RunPoint start) async {
  try {
    final place = (await Geocoding(
      locale: const Locale('ko', 'KR'),
    ).placemarkFromCoordinates(start.latitude, start.longitude)).firstOrNull;
    final city = [
      place?.locality,
      place?.subLocality,
    ].firstWhere((s) => s != null && s.isNotEmpty, orElse: () => null);
    final name = [
      place?.administrativeArea,
      city,
    ].where((s) => s != null && s.isNotEmpty).join(' ');
    return name.isEmpty ? null : name;
  } catch (_) {
    return null;
  }
}

Future<void> sharePng(Uint8List png) => SharePlus.instance.share(
  ShareParams(
    files: [XFile.fromData(png, mimeType: 'image/png')],
    fileNameOverrides: const ['wadadak-run.png'],
  ),
);
