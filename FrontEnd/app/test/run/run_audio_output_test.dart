import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/data/run_audio_output.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/run_audio_output');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late RunAudioOutput output;
  final requests = <int>[];
  Future<void> native(String method, int request) =>
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, {'requestId': request}),
        ),
        (_) {},
      );
  setUp(() {
    requests.clear();
    output = RunAudioOutput(channel: channel, supported: true);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initializeVoice') return true;
      if (call.method == 'speak') {
        requests.add((call.arguments as Map)['requestId'] as int);
        return true;
      }
      return null;
    });
  });
  tearDown(() async {
    await output.close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'late native completion/error cannot clear or fail a newer utterance',
    () async {
      var errors = 0;
      output.onError = () => errors++;
      expect(await output.initialize(), true);
      await output.speak('정기 안내');
      final old = requests.last;
      await output.speak('코스 이탈 확정');
      final current = requests.last;
      await native('voiceDone', old);
      await native('voiceError', old);
      expect(output.isSpeaking, true);
      expect(errors, 0);
      await native('voiceDone', current);
      expect(output.isSpeaking, false);
    },
  );

  test(
    'stop invalidates callbacks; current errors release priority and notify',
    () async {
      var errors = 0;
      output.onError = () => errors++;
      await output.initialize();
      await output.speak('중단할 안내');
      final old = requests.last;
      await output.stop();
      await native('voiceError', old);
      expect(output.isSpeaking, false);
      expect(errors, 0);
      await output.speak('새 안내');
      await native('voiceError', requests.last);
      expect(output.isSpeaking, false);
      expect(errors, 1);
    },
  );
}
