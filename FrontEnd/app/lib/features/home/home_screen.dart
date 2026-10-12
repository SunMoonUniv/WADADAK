import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/map/map_view.dart';

/// 홈(A2). 지금은 지도와 확대·현재 위치 버튼만 있다. 인사말·검색·필터·코스 목록 시트는 F2에서 붙인다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MapController? _map;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          children: [
            MapView(onCreated: (map) => _map = map),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(WdSpace.s16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: WdSpace.s12,
                    children: [
                      WdMapZoomControl(onZoomIn: () => _map?.zoomBy(1), onZoomOut: () => _map?.zoomBy(-1)),
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
