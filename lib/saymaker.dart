/// Generate images and video on [SayMaker](https://saymaker.ai).
///
/// One API key runs the whole shelf on your own credits: Veo 3.1, Kling 3.0,
/// Seedance 2.0, MiniMax H3, Nano Banana 2, GPT Image 2.5, Seedream 5.0 and
/// more. Create a key at https://saymaker.ai/settings/apikeys.
library saymaker;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The service this library talks to.
const baseUrl = 'https://saymaker.ai';

/// Where an API key is created.
const keysUrl = '$baseUrl/settings/apikeys';

/// The cheapest text-to-image model.
const modelImage = 'saymaker-image-v1';

/// The default edit model; it takes an input image.
const modelEdit = 'nano-banana-2-lite';

/// The video model a free account can run (480p or 768p, 4 to 15 seconds).
const modelVideo = 'minimax-h3-fast';

/// Model id -> the routing field the API expects next to it. Unlisted ids go as "kie".
const models = <String, String>{
  'saymaker-image-v1': 'kie',
  'nano-banana-2-lite': 'kie',
  'nano-banana-2': 'poyo',
  'nano-banana-pro': 'poyo',
  'gpt-image-2': 'poyo',
  'gpt-image-2-5-flare': 'kie',
  'seedream-5-lite': 'poyo',
  'seedream-5-pro': 'kie',
  'qwen-image-3-pro': 'kie',
  'grok-imagine-image-2-0': 'poyo',
  'minimax-h3-fast': 'vgenv',
  'minimax-h3': 'poyo',
  'seedance-2': 'kie',
  'seedance-2-fast': 'kie',
  'seedance-2-5': 'kie',
  'veo-3-1': 'kie',
  'kling-3-0': 'kie',
  'kling-3-0-turbo': 'kie',
  'wan-3-0': 'kie',
  'ltx-2-5-fast': 'replicate',
};

/// Why a call failed, split by what to do next.
enum SayMakerErrorKind {
  /// No API key, or the key is invalid or deleted.
  auth,

  /// The account is out of credits.
  quota,

  /// The model needs a paid plan or a credit pack.
  plan,

  /// Another run on this account is still rendering. Free accounts run one at a time.
  busy,

  /// The content filter or the model refused the prompt. Reword it.
  rejected,

  /// The deadline passed; the run may still finish in your SayMaker history.
  timeout,

  /// Anything else the service answered.
  other,
}

/// The only exception this library throws on purpose.
class SayMakerException implements Exception {
  /// What went wrong.
  final SayMakerErrorKind kind;

  /// The message, usually the service's own.
  final String message;

  /// Creates an exception.
  const SayMakerException(this.kind, this.message);

  @override
  String toString() => 'SayMakerException(${kind.name}): $message';
}

/// Map a refusal message to the error that says what to do next.
SayMakerException classify(String message, [Object? data]) {
  final low = message.toLowerCase();
  final busy = data is Map && data['busy'] != null;
  if (busy || low.contains('is rendering') || low.contains('at once')) {
    return SayMakerException(SayMakerErrorKind.busy, message);
  }
  if (low.contains('api key') || low.contains('no auth')) {
    return SayMakerException(SayMakerErrorKind.auth, message);
  }
  if (low.contains('insufficient credits')) {
    return SayMakerException(SayMakerErrorKind.quota, message);
  }
  if (low.contains('subscription') ||
      low.contains('plan') ||
      low.contains('sign in')) {
    return SayMakerException(SayMakerErrorKind.plan, message);
  }
  return SayMakerException(SayMakerErrorKind.other, message);
}

/// A SayMaker client. One per API key.
class SayMaker {
  /// The key from https://saymaker.ai/settings/apikeys.
  final String apiKey;

  /// The service root; only changed in tests.
  final String base;

  final http.Client _http;

  /// Creates a client. Pass [client] to reuse or fake the HTTP layer.
  SayMaker(this.apiKey, {this.base = baseUrl, http.Client? client})
      : _http = client ?? http.Client();

  /// Generate one image, or edit [imageUrl], and return its URL.
  ///
  /// For an edit the prompt names the change and what must stay.
  Future<String> generate(
    String prompt, {
    String? imageUrl,
    String? model,
    String? aspectRatio,
    Duration timeout = const Duration(minutes: 75),
    Duration pollEvery = const Duration(seconds: 5),
  }) {
    _checkUrl(imageUrl);
    final edit = imageUrl != null;
    final options = <String, Object?>{
      'size': aspectRatio ?? (edit ? 'auto' : '1:1'),
      'resolution': '1K',
      'n': 1,
      if (edit) 'image_input': [imageUrl],
    };
    return _run(
        'image',
        edit ? 'image-to-image' : 'text-to-image',
        model ?? (edit ? modelEdit : modelImage),
        prompt,
        options,
        timeout,
        pollEvery);
  }

  /// Generate one clip, or animate [imageUrl] as the first frame, and return its URL.
  Future<String> generateVideo(
    String prompt, {
    String? imageUrl,
    String model = modelVideo,
    int? duration,
    String? resolution,
    String aspectRatio = '16:9',
    bool sound = true,
    Duration timeout = const Duration(minutes: 90),
    Duration pollEvery = const Duration(seconds: 10),
  }) {
    _checkUrl(imageUrl);
    final options = <String, Object?>{
      'aspect_ratio': aspectRatio,
      'sound': sound,
      if (imageUrl != null) 'image_input': [imageUrl],
      if (duration != null) 'duration': duration,
      if (resolution != null) 'resolution': resolution,
    };
    return _run('video', imageUrl != null ? 'image-to-video' : 'text-to-video',
        model, prompt, options, timeout, pollEvery);
  }

  /// Close the underlying HTTP client.
  void close() => _http.close();

  void _checkUrl(String? u) {
    if (u != null && !(u.startsWith('http://') || u.startsWith('https://'))) {
      throw ArgumentError.value(u, 'imageUrl', 'must be a public http(s) url');
    }
  }

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final res = await _http.post(Uri.parse('$base$path'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $apiKey',
          'user-agent': 'saymaker-dart/0.1.0',
        },
        body: jsonEncode(body));
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }

  Future<String> _run(
      String media,
      String scene,
      String model,
      String prompt,
      Map<String, Object?> options,
      Duration timeout,
      Duration pollEvery) async {
    if (prompt.trim().isEmpty) throw ArgumentError('prompt is required');
    if (apiKey.isEmpty) {
      throw const SayMakerException(SayMakerErrorKind.auth,
          'an API key is required; create one at $keysUrl');
    }
    final env = await _post('/api/ai/generate', {
      'provider': models[model] ?? 'kie',
      'mediaType': media,
      'model': model,
      'scene': scene,
      'prompt': prompt,
      'options': options,
    });
    // Refusals answer HTTP 200 with code -1; the status code alone reads as success.
    if (env['code'] != 0)
      throw classify('${env['message'] ?? 'request refused'}', env['data']);
    final data = (env['data'] as Map?) ?? {};
    // A signed-out request is also a 200 with code 0 — only `wall` tells it apart.
    if (data['wall'] == true) {
      throw const SayMakerException(SayMakerErrorKind.auth,
          'an API key is required; create one at $keysUrl');
    }
    final id = data['id'];
    if (id == null)
      throw const SayMakerException(SayMakerErrorKind.other, 'no task id');

    // Free-account runs only reach the model on the poll that crosses the end
    // of the queue wait, so polling is what starts the work.
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollEvery);
      Map<String, dynamic> q;
      try {
        q = await _post('/api/ai/query', {'taskId': id});
      } catch (_) {
        continue; // a dropped poll is not a failed generation
      }
      if (q['code'] != 0) continue;
      final d = (q['data'] as Map?) ?? {};
      for (final field in ['cleanImages', 'images', 'videos']) {
        final list = d[field];
        if (list is List && list.isNotEmpty) return '${list.first}';
      }
      final status = '${d['status'] ?? ''}'.toLowerCase();
      if (status == 'failed' || status == 'error') {
        throw const SayMakerException(SayMakerErrorKind.rejected,
            'the run failed; reword the prompt rather than retrying');
      }
    }
    throw const SayMakerException(SayMakerErrorKind.timeout,
        'deadline passed; the run may still finish in your SayMaker history');
  }
}
