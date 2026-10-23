// Read-only integration check. Never prints bodies, tokens or auth headers.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:gamevault/services/hltb_provider.dart';

class ProbeClient extends http.BaseClient {
  final inner = http.Client();
  final requests = <Map<String, Object?>>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    requests.add({
      'method': request.method,
      'path': request.url.path,
      'status': response.statusCode,
      'contentType': response.headers['content-type'],
      'serverChallengeIndicated': response.headers.containsKey('cf-mitigated'),
    });
    return response;
  }

  @override
  void close() {
    inner.close();
    super.close();
  }
}

Future<void> main(List<String> args) async {
  final client = ProbeClient();
  final provider = WebsiteHltbProvider(client: client);
  try {
    final entries = await provider.search(
      args.isEmpty ? 'Elden Ring' : args.join(' '),
    );
    stdout.writeln(
      jsonEncode({
        'liveSuccess': true,
        'entries': entries.map((e) => e.toJson()).toList(),
        'requests': client.requests,
      }),
    );
  } on HltbFailure catch (e) {
    stdout.writeln(
      jsonEncode({
        'liveSuccess': false,
        'error': e.message,
        'state': e.state.name,
        'requests': client.requests,
      }),
    );
  } finally {
    client.close();
  }
}
