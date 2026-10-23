import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app/app_env.dart';
import 'backend_api_service.dart';
import 'session_store.dart';

class RealtimeUpdates {
  RealtimeUpdates(
      {http.Client Function()? createClient,
      Future<String?> Function()? tokenLoader,
      void Function()? onChanged})
      : _createClient = createClient ?? http.Client.new,
        _tokenLoader = tokenLoader ?? SessionStore().accessToken,
        _onChanged = onChanged ??
            (() => BackendApiService.instance.dataRevision.value++);
  final http.Client Function() _createClient;
  final Future<String?> Function() _tokenLoader;
  final void Function() _onChanged;
  http.Client? _client;
  StreamSubscription<String>? _subscription;
  Timer? _retry, _debounce;
  String? _user;
  int _generation = 0;
  void start(String? user) {
    if (_user == user) return;
    stop();
    _user = user;
    if (user != null) unawaited(_connect(_generation));
  }

  Future<void> _connect(int generation) async {
    try {
      final token = await _tokenLoader();
      if (generation != _generation || _user == null) return;
      if (token == null) {
        _scheduleRetry(generation);
        return;
      }
      final client = _createClient();
      _client = client;
      final uri = Uri.parse(
          '${AppEnv.backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/realtime');
      final response = await client
          .send(http.Request('GET', uri)
            ..headers['Authorization'] = 'Bearer $token'
            ..headers['Accept'] = 'text/event-stream')
          .timeout(const Duration(seconds: 10));
      if (generation != _generation) {
        client.close();
        return;
      }
      if (response.statusCode != 200 ||
          !(response.headers['content-type'] ?? '')
              .contains('text/event-stream')) {
        client.close();
        _scheduleRetry(generation);
        return;
      }
      var event = '';
      _subscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (generation != _generation) return;
        if (line.startsWith('event:')) event = line.substring(6).trim();
        if (line.isEmpty) event = '';
        if (!line.startsWith('data:') || event == 'ping') return;
        try {
          final data = jsonDecode(line.substring(5));
          if (data is! Map || data['type'] == 'connected') return;
          // Bound refresh latency even while events arrive continuously.
          _debounce ??= Timer(const Duration(milliseconds: 50), () {
            _debounce = null;
            if (generation == _generation) _onChanged();
          });
        } catch (_) {}
      },
              onDone: () => _scheduleRetry(generation),
              onError: (_) => _scheduleRetry(generation));
    } catch (_) {
      _scheduleRetry(generation);
    }
  }

  void _scheduleRetry(int generation) {
    if (generation != _generation ||
        _user == null ||
        (_retry?.isActive ?? false)) return;
    _subscription?.cancel();
    _client?.close();
    _retry = Timer(
        const Duration(seconds: 2), () => unawaited(_connect(generation)));
  }

  void stop() {
    _generation++;
    _user = null;
    _retry?.cancel();
    _debounce?.cancel();
    _debounce = null;
    _subscription?.cancel();
    _client?.close();
  }
}
