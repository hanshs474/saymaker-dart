import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saymaker/saymaker.dart';
import 'package:test/test.dart';

SayMaker fake(List<Map> calls, Map final_) =>
    SayMaker('sk', base: 'https://t', client: MockClient((r) async {
      final body = jsonDecode(r.body) as Map;
      calls.add(body);
      final data = r.url.path == '/api/ai/generate' ? {'id': 'row1'} : final_;
      return http.Response(jsonEncode({'code': 0, 'data': data}), 200);
    }));

void main() {
  test('image prefers the clean file', () async {
    final calls = <Map>[];
    final url = await fake(calls, {
      'images': ['m'],
      'cleanImages': ['c']
    }).generate('x', pollEvery: Duration.zero);
    expect(url, 'c');
    expect(calls[0]['model'], modelImage);
    expect(calls[1], {'taskId': 'row1'});
  });

  test('video routes by model', () async {
    final calls = <Map>[];
    final url = await fake(calls, {
      'videos': ['v']
    }).generateVideo('x', duration: 6, pollEvery: Duration.zero);
    expect(url, 'v');
    expect([
      calls[0]['provider'],
      calls[0]['scene'],
      calls[0]['options']['duration']
    ], [
      'vgenv',
      'text-to-video',
      6
    ]);
  });

  test('classify', () {
    expect(classify('insufficient credits').kind, SayMakerErrorKind.quota);
    expect(classify('invalid API key').kind, SayMakerErrorKind.auth);
    expect(
        classify('Your current run is rendering. Plans on the pricing page')
            .kind,
        SayMakerErrorKind.busy);
  });
}
