import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/member_api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/error_message.dart';

/// A1 · 스플래시 / 로그인. 저장된 로그인을 확인하는 동안에는 로고만 보인다.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;

  Future<void> _login(SocialProvider provider) async {
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).login(provider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
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
                    WdSocialLoginButton(WdSocialProvider.kakao, onPressed: loginWith(SocialProvider.kakao)),
                    // Apple 로그인은 보류했다. iOS 심사 전에는 추가해야 한다(App Store 심사 지침 4.8).
                    WdSocialLoginButton(WdSocialProvider.google, onPressed: loginWith(SocialProvider.google)),
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
