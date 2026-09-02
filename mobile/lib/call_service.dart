import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';

class AppCall {
  AppCall(this.raw);

  final Map<String, dynamic> raw;

  int get id => (raw['id'] as num).toInt();
  int get listingId => (raw['listing_id'] as num).toInt();
  String get listingTitle => '${raw['listing_title'] ?? ''}';
  int get callerId => (raw['caller_id'] as num).toInt();
  String get callerName => '${raw['caller_name'] ?? 'Пользователь'}';
  int get calleeId => (raw['callee_id'] as num).toInt();
  String get calleeName => '${raw['callee_name'] ?? 'Пользователь'}';
  String get status => '${raw['status'] ?? ''}';
  bool get calleeOnline => raw['callee_online'] == true;
  bool get calleeHasPush => raw['callee_has_push'] == true;
  bool get gsmFallback => raw['gsm_fallback'] == true;
  String? get gsmPhone {
    final v = raw['gsm_phone']?.toString();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  int get ringTimeoutSec => (raw['ring_timeout_sec'] as num?)?.toInt() ?? 40;
  int? get endedById => (raw['ended_by_id'] as num?)?.toInt();
  String? get endedByName {
    final v = raw['ended_by_name']?.toString();
    if (v == null || v.isEmpty) return null;
    return v;
  }
}

enum CallPhase { idle, outgoing, incoming, connecting, active, ended }

class CallService extends ChangeNotifier {
  CallService._();
  static final CallService instance = CallService._();

  ApiClient? _api;
  int? myUserId;
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  Timer? _reconnect;
  Timer? _ringTimer;
  Timer? _resendOffer;
  bool _connectingWs = false;
  bool _wantWs = false;

  RTCPeerConnection? _pc;
  MediaStream? localStream;
  MediaStream? remoteStream;
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _rendererReady = false;

  AppCall? call;
  CallPhase phase = CallPhase.idle;
  bool muted = false;
  bool speaker = true;
  String? lastError;
  String? endedBanner;
  bool offerGsm = false;
  DateTime? connectedAt;
  int inboxSeq = 0;
  Map<String, dynamic>? inboxEvent;
  bool _closing = false;
  Future<void> _signalTail = Future.value();

  bool get inCall => phase != CallPhase.idle;

  Future<void> attach(ApiClient api, {int? userId}) async {
    _api = api;
    if (userId != null) myUserId = userId;
    if (!_rendererReady) {
      await remoteRenderer.initialize();
      _rendererReady = true;
    }
  }

  Future<void> connect() async {
    _wantWs = true;
    final fresh = _ws == null;
    await _openWs();
    if (fresh) await _restorePending();
  }

  Future<void> disconnect() async {
    _wantWs = false;
    _reconnect?.cancel();
    await _hangupLocal(notifyServer: phase == CallPhase.outgoing || phase == CallPhase.active || phase == CallPhase.incoming);
    await _closeWs();
  }

  Future<void> _restorePending() async {
    final api = _api;
    if (api == null || inCall) return;
    try {
      final rows = await api.request('/calls/pending', auth: true);
      if (rows is! List || rows.isEmpty) return;
      final mine = Map<String, dynamic>.from(rows.first as Map);
      call = AppCall(mine);
      final status = call!.status;
      if (status == 'ringing') {
        phase = CallPhase.incoming;
        _startRingTimer();
        notifyListeners();
      } else if (status == 'active') {
        phase = CallPhase.connecting;
        notifyListeners();
        await _ensurePeer(offer: false);
      }
    } catch (_) {}
  }

  Future<void> handlePush(Map<String, dynamic> data) async {
    if (data['type']?.toString() != 'incoming_call') return;
    await connect();
    final id = int.tryParse('${data['call_id'] ?? ''}');
    if (id == null || _api == null) return;
    if (inCall && call?.id == id) return;
    try {
      final raw = await _api!.request('/calls/$id', auth: true) as Map<String, dynamic>;
      call = AppCall(raw);
      if (call!.status == 'ringing') {
        phase = CallPhase.incoming;
        lastError = null;
        offerGsm = false;
        _startRingTimer();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<bool> startCall({required int listingId, int? calleeId}) async {
    final api = _api;
    if (api == null) return false;
    if (inCall) {
      lastError = 'Сначала завершите текущий звонок';
      notifyListeners();
      return false;
    }
    if (!await _mic()) {
      lastError = 'Нужен доступ к микрофону';
      notifyListeners();
      return false;
    }
    lastError = null;
    offerGsm = false;
    try {
      final raw = await api.request(
        '/calls',
        method: 'POST',
        auth: true,
        body: {
          'listing_id': listingId,
          if (calleeId != null) 'callee_id': calleeId,
        },
      ) as Map<String, dynamic>;
      call = AppCall(raw);
      phase = CallPhase.outgoing;
      notifyListeners();
      await connect();
      await _ensurePeer(offer: true);
      _startRingTimer();
      return true;
    } on ApiException catch (e) {
      lastError = e.message;
      phase = CallPhase.idle;
      notifyListeners();
      return false;
    } catch (e) {
      lastError = ApiClient.serverUnreachableMessage;
      phase = CallPhase.idle;
      notifyListeners();
      return false;
    }
  }

  Future<void> accept() async {
    if (call == null || phase != CallPhase.incoming) return;
    if (!await _mic()) {
      lastError = 'Нужен доступ к микрофону';
      notifyListeners();
      return;
    }
    try {
      phase = CallPhase.connecting;
      notifyListeners();
      await _api?.request('/calls/${call!.id}/accept', method: 'POST', auth: true);
      await _ensurePeer(offer: false);
      if (_pendingOffer != null) {
        await _applyIncomingOffer(_pendingOffer!);
        _pendingOffer = null;
      }
    } on ApiException catch (e) {
      lastError = e.message;
      phase = CallPhase.ended;
      offerGsm = call?.gsmFallback == true;
      notifyListeners();
    }
  }

  Future<void> decline() async {
    final id = call?.id;
    await _hangupLocal(notifyServer: false);
    if (id != null) {
      try {
        await _api?.request('/calls/$id/decline', method: 'POST', auth: true);
      } catch (_) {}
    }
  }

  Future<void> hangup({String reason = 'hangup'}) async {
    if (_closing) return;
    final id = call?.id;
    final gsm = call?.gsmFallback == true && (reason == 'timeout' || reason == 'failed');
    final banner = (phase == CallPhase.active || phase == CallPhase.connecting) ? 'Вы завершили звонок' : null;
    await _closeCall(banner: banner, notifyServer: false);
    if (id != null) {
      try {
        await _api?.request(
          '/calls/$id/hangup',
          method: 'POST',
          auth: true,
          body: {'reason': reason},
        );
      } catch (_) {}
    }
    if (gsm) {
      offerGsm = true;
      lastError = reason == 'timeout'
          ? 'Абонент не ответил в приложении'
          : 'Не удалось соединить через интернет';
      notifyListeners();
    }
  }

  Future<void> toggleMute() async {
    muted = !muted;
    localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    await Helper.setSpeakerphoneOn(speaker);
    notifyListeners();
  }

  Future<void> _closeCall({String? banner, required bool notifyServer}) async {
    if (_closing) return;
    _closing = true;
    try {
      _ringTimer?.cancel();
      _resendOffer?.cancel();
      final id = call?.id;
      final wasOpen = phase == CallPhase.outgoing ||
          phase == CallPhase.incoming ||
          phase == CallPhase.active ||
          phase == CallPhase.connecting;
      try {
        await _pc?.close();
      } catch (_) {}
      _pc = null;
      try {
        await localStream?.dispose();
      } catch (_) {}
      localStream = null;
      remoteStream = null;
      _pendingOffer = null;
      _pendingIce.clear();
      _hasRemote = false;
      if (notifyServer && wasOpen && id != null) {
        try {
          await _api?.request('/calls/$id/hangup', method: 'POST', auth: true, body: {'reason': 'hangup'});
        } catch (_) {}
      }
      if (banner != null && banner.isNotEmpty) {
        endedBanner = banner;
        phase = CallPhase.ended;
        notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 1400));
      } else if (phase != CallPhase.idle) {
        phase = CallPhase.ended;
        notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 280));
      }
      phase = CallPhase.idle;
      call = null;
      connectedAt = null;
      endedBanner = null;
      notifyListeners();
    } finally {
      _closing = false;
    }
  }

  Future<void> _hangupLocal({required bool notifyServer}) async {
    await _closeCall(banner: null, notifyServer: notifyServer);
  }

  void _markActive() {
    if (phase == CallPhase.idle || phase == CallPhase.ended) return;
    final became = phase != CallPhase.active;
    phase = CallPhase.active;
    connectedAt ??= DateTime.now();
    _ringTimer?.cancel();
    if (became) notifyListeners();
  }

  void _dispatchInbox(Map<String, dynamic> msg) {
    inboxEvent = msg;
    inboxSeq++;
    notifyListeners();
  }

  void _startResendOffer() {
    _resendOffer?.cancel();
    _resendOffer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_hasRemote) {
        _resendOffer?.cancel();
        return;
      }
      if (phase != CallPhase.outgoing && phase != CallPhase.connecting) {
        _resendOffer?.cancel();
        return;
      }
      try {
        final local = await _pc?.getLocalDescription();
        if (local != null && call != null) {
          _send({'type': 'offer', 'call_id': call!.id, 'sdp': local.sdp, 'sdp_type': local.type});
        }
      } catch (_) {}
    });
  }

  void _startRingTimer() {
    _ringTimer?.cancel();
    final sec = call?.ringTimeoutSec ?? 40;
    _ringTimer = Timer(Duration(seconds: sec), () {
      if (phase == CallPhase.outgoing || phase == CallPhase.incoming) {
        hangup(reason: 'timeout');
      }
    });
  }

  Future<bool> _mic() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Map<String, dynamic>? _pendingOffer;
  final List<Map<String, dynamic>> _pendingIce = [];
  bool _hasRemote = false;

  List<Map<String, dynamic>> _iceServersCached = [
    {
      'urls': [
        'stun:stun.cloudflare.com:3478',
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    },
  ];
  DateTime? _iceServersAt;

  Future<List<Map<String, dynamic>>> _loadIceServers() async {
    final api = _api;
    final stale = _iceServersAt == null || DateTime.now().difference(_iceServersAt!) > const Duration(minutes: 8);
    if (api != null && stale) {
      try {
        final data = await api.request('/calls/ice-servers', auth: true);
        if (data is Map && data['ice_servers'] is List) {
          final rows = <Map<String, dynamic>>[];
          for (final row in data['ice_servers'] as List) {
            if (row is! Map) continue;
            rows.add(Map<String, dynamic>.from(row));
          }
          if (rows.isNotEmpty) {
            _iceServersCached = rows;
            _iceServersAt = DateTime.now();
          }
        }
      } catch (_) {}
    }
    return _iceServersCached;
  }

  Future<void> _ensurePeer({required bool offer}) async {
    if (_pc != null) return;
    final ice = await _loadIceServers();
    final config = {
      'iceServers': ice,
      'sdpSemantics': 'unified-plan',
    };
    _pc = await createPeerConnection(config);
    _pc!.onIceCandidate = (c) {
      if (c.candidate == null || call == null) return;
      _send({
        'type': 'ice',
        'call_id': call!.id,
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _markActive();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        hangup(reason: 'failed');
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        // короткие обрывы LTE — не рвём сразу
      }
    };
    _pc!.onIceConnectionState = (s) {
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _markActive();
      }
    };
    _pc!.onTrack = (ev) {
      if (ev.streams.isNotEmpty) {
        remoteStream = ev.streams.first;
        remoteRenderer.srcObject = remoteStream;
        notifyListeners();
      }
    };
    localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    for (final t in localStream!.getTracks()) {
      await _pc!.addTrack(t, localStream!);
    }
    await Helper.setSpeakerphoneOn(speaker);
    if (offer) {
      final desc = await _pc!.createOffer({'offerToReceiveAudio': 1, 'offerToReceiveVideo': 0});
      await _pc!.setLocalDescription(desc);
      _send({'type': 'offer', 'call_id': call!.id, 'sdp': desc.sdp, 'sdp_type': desc.type});
      _startResendOffer();
    }
  }

  Future<void> _onSignal(Map<String, dynamic> msg) async {
    try {
      await _onSignalInner(msg);
    } catch (_) {}
  }

  Future<void> _onSignalInner(Map<String, dynamic> msg) async {
    final type = msg['type']?.toString();
    if (type == 'chat' || type == 'chat_read') {
      _dispatchInbox(msg);
      return;
    }
    if (type == 'incoming') {
      final raw = Map<String, dynamic>.from(msg['call'] as Map);
      if (inCall && call?.id != (raw['id'] as num).toInt()) return;
      call = AppCall(raw);
      phase = CallPhase.incoming;
      lastError = null;
      offerGsm = false;
      _startRingTimer();
      notifyListeners();
      return;
    }
    if (type == 'accepted') {
      if (phase == CallPhase.outgoing) {
        phase = CallPhase.connecting;
        notifyListeners();
      }
      return;
    }
    if (type == 'hangup') {
      if (_closing) return;
      final raw = msg['call'];
      if (raw is Map) call = AppCall(Map<String, dynamic>.from(raw));
      final endedBy = call?.endedById;
      final self = endedBy != null && endedBy == myUserId;
      String? banner;
      if (phase == CallPhase.active || phase == CallPhase.connecting) {
        banner = self ? 'Вы завершили звонок' : '${call?.endedByName ?? 'Собеседник'} завершил звонок';
      }
      await _closeCall(banner: banner, notifyServer: false);
      return;
    }
    if (type == 'offer') {
      _pendingOffer = {'sdp': msg['sdp'], 'type': msg['sdp_type'] ?? 'offer'};
      if (_pc != null && (phase == CallPhase.connecting || phase == CallPhase.active)) {
        await _applyIncomingOffer(_pendingOffer!);
        _pendingOffer = null;
      }
      return;
    }
    if (type == 'answer') {
      await _applyRemoteAnswer(msg['sdp']?.toString(), msg['sdp_type']?.toString());
      return;
    }
    if (type == 'ice') {
      final cand = {
        'candidate': msg['candidate'],
        'sdpMid': msg['sdpMid'],
        'sdpMLineIndex': msg['sdpMLineIndex'],
      };
      if (!_hasRemote) {
        _pendingIce.add(cand);
        return;
      }
      await _addIce(cand);
    }
  }

  Future<void> _applyIncomingOffer(Map<String, dynamic> offer) async {
    final pc = _pc;
    if (pc == null) return;
    final sdp = offer['sdp']?.toString();
    final typ = offer['type']?.toString() ?? 'offer';
    if (sdp == null || sdp.isEmpty) return;
    if (_hasRemote) {
      await _resendLocalAnswer();
      return;
    }
    if (pc.signalingState != RTCSignalingState.RTCSignalingStateStable) return;
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, typ));
      _hasRemote = true;
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      if (call != null) {
        _send({'type': 'answer', 'call_id': call!.id, 'sdp': answer.sdp, 'sdp_type': answer.type});
      }
      await _drainIce();
    } catch (_) {}
  }

  Future<void> _applyRemoteAnswer(String? sdp, String? type) async {
    final pc = _pc;
    if (pc == null || sdp == null || sdp.isEmpty) return;
    if (_hasRemote || pc.signalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      return;
    }
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type ?? 'answer'));
      _hasRemote = true;
      _resendOffer?.cancel();
      await _drainIce();
    } catch (_) {}
  }

  Future<void> _resendLocalAnswer() async {
    try {
      final local = await _pc?.getLocalDescription();
      if (local == null || call == null || local.type != 'answer') return;
      _send({'type': 'answer', 'call_id': call!.id, 'sdp': local.sdp, 'sdp_type': local.type});
    } catch (_) {}
  }

  Future<void> _drainIce() async {
    for (final c in List<Map<String, dynamic>>.from(_pendingIce)) {
      await _addIce(c);
    }
    _pendingIce.clear();
  }

  Future<void> _addIce(Map<String, dynamic> cand) async {
    try {
      await _pc?.addCandidate(
        RTCIceCandidate(
          cand['candidate']?.toString(),
          cand['sdpMid']?.toString(),
          (cand['sdpMLineIndex'] as num?)?.toInt(),
        ),
      );
    } catch (_) {}
  }

  Uri? _wsUri(String token) {
    final api = _api;
    if (api == null) return null;
    final http = Uri.parse(api.baseUrl);
    if (http.host.isEmpty) return null;
    final scheme = http.scheme == 'https' ? 'wss' : 'ws';
    var path = http.path;
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    path = '$path/calls/ws';
    final defaultPort = scheme == 'wss' ? 443 : 80;
    final explicit = http.hasPort && http.port != 0 && http.port != defaultPort;
    final origin = explicit ? '$scheme://${http.host}:${http.port}' : '$scheme://${http.host}';
    return Uri.parse('$origin$path').replace(queryParameters: {'token': token});
  }

  Future<void> _openWs() async {
    if (_connectingWs || !_wantWs) return;
    final api = _api;
    if (api == null) return;
    final token = await api.token;
    if (token == null || token.isEmpty) return;
    final uri = _wsUri(token);
    if (uri == null) return;
    _connectingWs = true;
    try {
      await _closeWs();
      _ws = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $token'},
        pingInterval: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 12),
      );
      await _ws!.ready;
      _wsSub = _ws!.stream.listen(
        (event) {
          try {
            final msg = jsonDecode(event as String);
            if (msg is Map<String, dynamic>) {
              _signalTail = _signalTail.then((_) => _onSignal(msg)).catchError((_) {});
            }
          } catch (_) {}
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
    } catch (_) {
      if (phase == CallPhase.outgoing || phase == CallPhase.incoming || phase == CallPhase.connecting) {
        lastError = 'Нет связи для звонка. Проверьте интернет';
        notifyListeners();
      }
      _scheduleReconnect();
    } finally {
      _connectingWs = false;
    }
  }

  void _scheduleReconnect() {
    _wsSub = null;
    _ws = null;
    if (!_wantWs) return;
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 2), _openWs);
  }

  Future<void> _closeWs() async {
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _ws?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }
}
