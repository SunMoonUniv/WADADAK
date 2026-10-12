import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/map/map_view.dart';
import '../../routes.dart';

/// 홈(A2). 지금은 지도, `＋ 코스 만들기`, 현재 위치 버튼만 있다. 인사말·검색·필터·코스 목록 시트는 F2에서 붙인다.
/// 확대·축소 버튼은 두지 않는다(정책 MAP-02, 제스처로 한다).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MapController? _map;

  /// 지금 보고 있는 지도 위치. 코스 만들기를 같은 곳에서 시작한다(A2-07).
  MapCamera? _camera;

  // 위아래 여백 + 현재 위치 버튼.
  static const _buttonRowHeight = WdSpace.s16 * 2 + WdMapLocateButton.size;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          children: [
            MapView(
              // 아래 버튼 줄만큼 비워 네이버 로고·축척이 버튼에 가리지 않게 한다.
              padding: const EdgeInsets.only(bottom: _buttonRowHeight),
              onCreated: (map) => _map = map,
              onCameraIdle: (camera) => _camera = camera,
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(WdSpace.s16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Figma A4·A5와 같이 왼쪽 24.
                      Padding(
                        padding: const EdgeInsets.only(left: WdSpace.s8),
                        child: WdMapPillButton.small(
                          '＋ 코스 만들기',
                          onPressed: () => context.push(Routes.courseCreate, extra: _camera),
                        ),
                      ),
                      WdMapLocateButton(onPressed: () => _map?.showMyLocation()),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
