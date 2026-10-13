import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/member_api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/social_login.dart';
import '../../core/error_message.dart';

/// A1 · 스플래시 / 로그인. 저장된 로그인을 확인하는 동안에는 로고만 보인다.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// 로그인 중에는 버튼을 잠가 두 번 눌러도 로그인이 한 번만 진행되게 한다.
  bool _busy = false;

  /// 소셜 로그인이 끝나 서버 로그인을 기다리는 중. 서버 요청은 시간 제한으로 반드시 끝나므로 이때는 잠금을 풀지 않는다.
  bool _waitingForServer = false;

  /// 지금 진행 중인 로그인 번호. 버려진 로그인이 뒤늦게 끝나도 새 로그인의 잠금을 건드리지 않게 한다.
  int _attempt = 0;

  /// 로그인 창(카카오톡·카카오 웹·Google)을 띄운 채 앱을 떠났다 돌아오면 소셜 SDK가 성공도 취소도 알려주지 않을 수 있다.
  /// 돌아온 뒤 [_abandonedLoginTimeout]이 지나도 소셜 로그인이 끝나지 않으면 버려진 로그인으로 보고 잠금을 푼다.
  late final AppLifecycleListener _lifecycle;
  Timer? _unlockTimer;
  static const _abandonedLoginTimeout = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _unlockTimer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _onResume() {
    if (!_busy || _waitingForServer) return;
    final attempt = _attempt;
    _unlockTimer?.cancel();
    _unlockTimer = Timer(_abandonedLoginTimeout, () {
      if (mounted && attempt == _attempt && !_waitingForServer) setState(() => _busy = false);
    });
  }

  Future<void> _login(SocialProvider provider) async {
    final attempt = ++_attempt;
    _unlockTimer?.cancel();
    setState(() {
      _busy = true;
      _waitingForServer = false;
    });
    try {
      await ref.read(authControllerProvider.notifier).login(provider, onSocialSignedIn: () {
        if (attempt != _attempt) return;
        _unlockTimer?.cancel();
        _waitingForServer = true;
      });
    } on SocialLoginCanceled {
      // 로그인 창을 닫았으면 안내 없이 그대로 둔다.
    } catch (e) {
      if (mounted && attempt == _attempt) showError(context, e);
    } finally {
      if (mounted && attempt == _attempt) {
        _unlockTimer?.cancel();
        setState(() {
          _busy = false;
          _waitingForServer = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final checking = ref.watch(authControllerProvider).isLoading;
    VoidCallback? loginWith(SocialProvider provider) => _busy ? null : () => _login(provider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
          child: Column(
            spacing: WdSpace.s16,
            children: [
              const Spacer(),
              const _SplashLogo(),
              const Spacer(),
              // 확인하는 동안에도 버튼 자리를 둬서 로고가 움직이지 않게 한다.
              Visibility(
                visible: !checking,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: WdSpace.s16,
                  children: [
                    // 로그인 중에는 버튼 자리에 로딩을 보여준다(A1-1). 버튼 자리를 그대로 둬서 로고가 움직이지 않게 한다.
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Visibility(
                          visible: !_busy,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            spacing: WdSpace.s16,
                            children: [
                              WdSocialLoginButton(WdSocialProvider.kakao, onPressed: loginWith(SocialProvider.kakao)),
                              // Apple 로그인은 보류했다. iOS 심사 전에는 추가해야 한다(App Store 심사 지침 4.8).
                              WdSocialLoginButton(WdSocialProvider.google, onPressed: loginWith(SocialProvider.google)),
                            ],
                          ),
                        ),
                        if (_busy) const _LoginProgress(),
                      ],
                    ),
                    Text(
                      '소셜 계정으로만 가입할 수 있어요',
                      textAlign: TextAlign.center,
                      style: WdText.label12.copyWith(color: WdColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A1-1 · 로그인 중. 회색 링 위에 잉크색 호가 도는 스피너와 안내 문구.
class _LoginProgress extends StatelessWidget {
  const _LoginProgress();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        spacing: WdSpace.s12,
        children: [
          const SizedBox.square(
            dimension: 32,
            child: CircularProgressIndicator(strokeWidth: 3.2, color: WdColors.ink, backgroundColor: WdColors.line),
          ),
          Text('로그인하는 중이에요', style: WdText.label12.copyWith(color: WdColors.muted)),
        ],
      );
}

/// Brand / Splash logo — 앱 마크 · 워드마크 · 태그라인.
class _SplashLogo extends StatelessWidget {
  const _SplashLogo();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        spacing: WdSpace.s14,
        children: [
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: WdColors.ink, borderRadius: BorderRadius.circular(24)),
            child: const WdIcon(WdIcons.brandGhost, size: 72),
          ),
          const WdLogo(height: 42, wordmarkOnly: true),
          Text(
            '코스를 공유하고, 고스트와 달린다',
            style: WdText.raw(14, FontWeight.w400, 14 * 1.4).copyWith(color: WdColors.muted),
          ),
        ],
      );
}
