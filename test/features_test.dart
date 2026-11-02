import 'dart:convert';
import 'dart:io';

import 'package:file_chat/core/ai.dart';
import 'package:file_chat/core/models.dart';
import 'package:file_chat/core/strings.dart';
import 'package:file_chat/core/voice.dart';
import 'package:file_chat/ui/message_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('search', () {
    final c = Conversation(id: '1', title: 'عقد الإيجار', messages: [
      Message(id: 'a', role: Role.user, text: 'ما مدّة العقد؟'),
      Message(
          id: 'b',
          role: Role.assistant,
          text: 'المقدمة\n**مدة الإيجار** سنة واحدة تبدأ من تاريخ التوقيع، ويجدد تلقائيًا ما لم يُخطر أحد الطرفين.\nالمصدر: عقد.pdf، صفحة 2'),
    ]);

    test('ignores diacritics and hamza forms', () {
      expect(c.matches('مدة'), isTrue, reason: 'مدّة with shadda');
      expect(c.matches('الايجار'), isTrue, reason: 'الإيجار with hamza');
      expect(c.matches('تلقائيا'), isTrue);
      expect(c.matches('غير موجود'), isFalse);
    });

    test('shows the matching line, not the title', () {
      expect(c.snippet('عقد الايجار'), isNull, reason: 'the title already shows it');
      final sn = c.snippet('يجدد')!;
      expect(sn, contains('يجدد'));
      expect(sn, isNot(contains('**')));
      expect(c.snippet('صفحة 2'), 'المصدر: عقد.pdf، صفحة 2');
    });
  });

  test('a shared answer carries the question and the answer with its source', () {
    final v = MessageView(
      message: Message(id: 'r', role: Role.assistant, text: 'الإجمالي 120 ريال.\nالمصدر: فاتورة.pdf'),
      question: 'كم الإجمالي؟',
      s: S('ar'),
      isLast: true,
      onRetry: () async {},
      onDeleteFile: (_) {},
    );
    final t = v.shareText();
    expect(t, contains('كم الإجمالي؟'));
    expect(t, contains('المصدر: فاتورة.pdf'));
    expect(t, contains('قارئ الملفات'));
  });

  group('voice', () {
    late File audio;
    setUp(() async {
      audio = File('${Directory.systemTemp.path}/voice-test.m4a')..writeAsBytesSync(List.filled(4000, 1));
    });

    test('sends the recording to the proxy and returns the text', () async {
      late http.BaseRequest seen;
      final v = Voice(
        proxy: const Proxy('https://proxy.example', 'tok'),
        client: MockClient.streaming((req, body) async {
          seen = req;
          final bytes = await body.toBytes();
          expect(utf8.decode(bytes, allowMalformed: true), contains('whisper-large-v3-turbo'));
          return http.StreamedResponse(Stream.value(utf8.encode('{"text":" كم مدة العقد؟ "}')), 200);
        }),
      );
      final text = await v.transcribe(audio, {'x-user-token': 'id', 'x-question-id': 'q'});
      expect(text, 'كم مدة العقد؟');
      expect(seen.url.toString(), 'https://proxy.example/q/v1/audio/transcriptions');
      expect(seen.headers['x-kind'], 'voice');
      expect(seen.headers['x-app-token'], 'tok');
      expect(seen.headers['x-user-token'], 'id');
    });

    test('the daily limit and sign-in errors are told apart', () async {
      Voice reply(int code, String why) => Voice(
            proxy: const Proxy('https://proxy.example', 'tok'),
            client: MockClient((_) async => http.Response(why, code, headers: {'x-proxy-error': why})),
          );
      expect(() => reply(429, 'quota').transcribe(audio, {}),
          throwsA(isA<VoiceError>().having((e) => e.code, 'code', 'quota')));
      expect(() => reply(401, 'auth').transcribe(audio, {}),
          throwsA(isA<VoiceError>().having((e) => e.code, 'code', 'signIn')));
      expect(() => reply(500, 'x').transcribe(audio, {}),
          throwsA(isA<VoiceError>().having((e) => e.code, 'code', 'failed')));
    });

    test('silence gives a clear message', () async {
      final v = Voice(
        proxy: const Proxy('https://proxy.example', 'tok'),
        client: MockClient((_) async => http.Response('{"text":"  "}', 200)),
      );
      expect(() => v.transcribe(audio, {}), throwsA(isA<VoiceError>().having((e) => e.code, 'code', 'empty')));
    });
  });

  test('every voice error has a message in both languages', () {
    for (final lang in ['ar', 'en']) {
      for (final code in ['mic', 'quota', 'signIn', 'empty', 'failed']) {
        final k = 'voice_$code';
        expect(S(lang).t(k), isNot(k), reason: '$lang $k');
      }
    }
  });
}
