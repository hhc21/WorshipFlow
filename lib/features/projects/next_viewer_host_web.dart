// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

import '../../core/ops/ops_metrics.dart';
import '../../core/runtime/runtime_guard.dart';
import 'next_viewer_contract.dart';

Widget buildNextViewerHostView(NextViewerHostProps props) {
  return _NextViewerHostWeb(props: props);
}

class _NextViewerHostWeb extends StatefulWidget {
  final NextViewerHostProps props;

  const _NextViewerHostWeb({required this.props});

  @override
  State<_NextViewerHostWeb> createState() => _NextViewerHostWebState();
}

class _NextViewerHostWebState extends State<_NextViewerHostWeb> {
  static int _viewTypeSeed = 0;

  late final String _viewType;
  late final html.IFrameElement _iframe;
  StreamSubscription<html.MessageEvent>? _messageSub;
  int _requestSeed = 0;

  bool _viewerReady = false;
  String _lastInitSignature = '';
  int _lastSyncRevision = -1;
  String? _targetOrigin;
  Set<String> _allowedOrigins = const <String>{};

  @override
  void initState() {
    super.initState();
    _viewType = 'wf-next-viewer-${_viewTypeSeed++}';
    _targetOrigin = _resolveOrigin(widget.props.viewerUrl);
    _allowedOrigins = _resolveAllowedOrigins(widget.props.viewerUrl);
    _iframe = html.IFrameElement()
      ..src = _buildViewerUrl(widget.props.viewerUrl)
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block'
      ..allow = 'clipboard-read; clipboard-write';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      return _iframe;
    });

    _messageSub = html.window.onMessage.listen(_handleMessage);
    OpsMetrics.emit(
      'livecue_session_metric',
      fields: <String, Object?>{
        'event': 'viewer_host_init',
        'viewerUrl': widget.props.viewerUrl,
      },
    );
  }

  @override
  void didUpdateWidget(covariant _NextViewerHostWeb oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldProps = oldWidget.props;
    final newProps = widget.props;

    if (oldProps.viewerUrl != newProps.viewerUrl) {
      _targetOrigin = _resolveOrigin(newProps.viewerUrl);
      _allowedOrigins = _resolveAllowedOrigins(newProps.viewerUrl);
      _viewerReady = false;
      _lastInitSignature = '';
      _lastSyncRevision = -1;
      _iframe.src = _buildViewerUrl(newProps.viewerUrl);
      _log('viewer url updated; waiting for viewer-ready');
      return;
    }

    if (!_viewerReady) {
      return;
    }

    final tokenChanged = oldProps.initData.idToken != newProps.initData.idToken;
    if (tokenChanged) {
      _postMessage(
        type: 'token-refresh',
        payload: <String, Object?>{'idToken': newProps.initData.idToken},
      );
    }

    if (oldProps.syncRevision != newProps.syncRevision &&
        _lastSyncRevision != newProps.syncRevision) {
      _postMessage(
        type: 'ink-synced',
        payload: <String, Object?>{
          'dirty': false,
          'syncRevision': newProps.syncRevision,
          'syncedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      _lastSyncRevision = newProps.syncRevision;
      newProps.onDirtyChanged(false);
    }

    _sendHostInitIfNeeded(force: false);
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    OpsMetrics.emit(
      'livecue_session_metric',
      fields: <String, Object?>{
        'event': 'viewer_host_dispose',
        'viewerUrl': widget.props.viewerUrl,
      },
    );
    super.dispose();
  }

  void _handleMessage(html.MessageEvent event) {
    if (!identical(event.source, _iframe.contentWindow)) {
      return;
    }
    if (!_isAllowedOrigin(event.origin)) {
      return;
    }

    final envelope = _parseEnvelope(event.data);
    if (envelope == null) {
      return;
    }

    final type = envelope['type']?.toString() ?? '';
    final payload = _asObjectMap(envelope['payload']) ?? <String, Object?>{};
    switch (type) {
      case 'viewer-ready':
        _viewerReady = true;
        _log('viewer-ready received');
        _sendHostInitIfNeeded(force: true);
        break;
      case 'init-applied':
        widget.props.onDirtyChanged(false);
        _log('init-applied acknowledged');
        break;
      case 'ink-dirty':
        widget.props.onDirtyChanged(true);
        break;
      case 'ink-synced':
        widget.props.onDirtyChanged(false);
        break;
      case 'ink-commit':
        widget.props.onInkCommit(NextViewerInkState.fromPayload(payload));
        break;
      case 'asset-cors-failed':
        widget.props.onAssetError(
          NextViewerAssetError(
            code: payload['code']?.toString() ?? 'asset-cors-failed',
            message:
                payload['message']?.toString() ?? 'Viewer image load failed',
            url: payload['url']?.toString(),
          ),
        );
        break;
      default:
        _log('unhandled viewer event: $type');
        break;
    }
  }

  void _sendHostInitIfNeeded({required bool force}) {
    if (!_viewerReady) return;

    final payload = widget.props.initData.toPayload();
    final validInitPayload = RuntimeGuard.guardHostViewerInitPayload(
      payload,
      fields: <String, Object?>{'viewerUrl': widget.props.viewerUrl},
    );
    if (!validInitPayload) {
      OpsMetrics.liveCueStateInvalid(
        fields: <String, Object?>{
          'reason': 'host_init_payload_invalid',
          'viewerUrl': widget.props.viewerUrl,
        },
      );
      return;
    }
    final signature = jsonEncode(payload);
    if (!force && signature == _lastInitSignature) {
      return;
    }

    _postMessage(type: 'host-init', payload: payload);
    _lastInitSignature = signature;
  }

  void _postMessage({
    required String type,
    required Map<String, Object?> payload,
  }) {
    final targetWindow = _iframe.contentWindow;
    if (targetWindow == null) {
      _log('iframe contentWindow is null; skip message $type');
      return;
    }
    final requestId =
        '$type-${DateTime.now().microsecondsSinceEpoch}-${_requestSeed++}';
    final envelope = <String, Object?>{
      'type': type,
      'version': 'v1',
      'requestId': requestId,
      'payload': payload,
    };
    final targetOrigin = _targetOrigin;
    if (targetOrigin == null || !_allowedOrigins.contains(targetOrigin)) {
      _log('blocked outbound message($type): target origin not whitelisted');
      OpsMetrics.runtimeGuardTriggered(
        guard: 'viewer_target_origin_not_whitelisted',
        fields: <String, Object?>{
          'eventType': type,
          'viewerUrl': widget.props.viewerUrl,
        },
      );
      return;
    }
    targetWindow.postMessage(envelope, targetOrigin);
  }

  Map<String, Object?>? _parseEnvelope(Object? raw) {
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        return _asObjectMap(decoded);
      } on FormatException {
        return null;
      }
    }
    return _asObjectMap(raw);
  }

  Map<String, Object?>? _asObjectMap(Object? value) {
    if (value is! Map) return null;
    final out = <String, Object?>{};
    for (final entry in value.entries) {
      out[entry.key.toString()] = entry.value;
    }
    return out;
  }

  bool _isAllowedOrigin(String origin) {
    if (_allowedOrigins.isEmpty) {
      return false;
    }
    return _allowedOrigins.contains(origin);
  }

  String? _resolveOrigin(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
      return null;
    }
    final scheme = parsed.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    final port = parsed.hasPort ? ':${parsed.port}' : '';
    return '$scheme://${parsed.host}$port';
  }

  Set<String> _resolveAllowedOrigins(String viewerUrl) {
    final targetOrigin = _resolveOrigin(viewerUrl);
    if (targetOrigin == null) {
      _log('invalid viewer url origin: $viewerUrl');
      return const <String>{};
    }
    return <String>{targetOrigin};
  }

  String _buildViewerUrl(String viewerUrl) {
    final parsed = Uri.tryParse(viewerUrl);
    final hostOrigin = html.window.location.origin;
    if (parsed == null || !parsed.hasAuthority) {
      return viewerUrl;
    }
    final currentHostOrigin = hostOrigin.trim();
    if (currentHostOrigin.isEmpty) {
      return parsed.toString();
    }
    final current = Map<String, String>.from(parsed.queryParameters);
    current['hostOrigin'] = currentHostOrigin;
    return parsed.replace(queryParameters: current).toString();
  }

  void _log(String message) {
    widget.props.onProtocolLog?.call(message);
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
