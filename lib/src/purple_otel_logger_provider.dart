import 'package:purple_logger/purple_logger.dart' show EventLogger, LogEvent, LoggerConvenience;
import 'package:purple_logger_otel/purple_logger_otel.dart';
import 'package:purple_otel_api/purple_otel_api.dart' as otel;

final class PurpleOtelLoggerProvider extends OtelLoggerProvider {
  final otel.LoggerProvider _otelProvider;

  PurpleOtelLoggerProvider({required otel.LoggerProvider otelProvider})
      : _otelProvider = otelProvider;

  @override
  OtelLogger createOtelLogger(String category) {
    return _PurpleOtelLogger(
      category: category,
      otelProvider: _otelProvider,
    );
  }

  @override
  void dispose() {
    _otelProvider.shutdown();
    super.dispose();
  }
}

final class _PurpleOtelLogger extends OtelLogger with OtelSeverityMapping, LoggerConvenience implements EventLogger {
  final otel.LoggerProvider _otelProvider;
  otel.Logger? _otelLogger;

  _PurpleOtelLogger({
    required super.category,
    required otel.LoggerProvider otelProvider,
  }) : _otelProvider = otelProvider;

  otel.Logger _getLogger() =>
      _otelLogger ??= _otelProvider.get(category);

  @override
  void write(LogEvent event) {
    final allProps = <String, Object?>{};
    allProps.addAll(event.scopeProperties);
    allProps.addAll(event.properties);
    if (event.error != null) {
      allProps['error.type'] = event.error.runtimeType.toString();
      allProps['error.message'] = event.error.toString();
    }
    if (event.stackTrace != null) {
      allProps['error.stackTrace'] = event.stackTrace.toString();
    }
    final traceCtx = extractTraceContext();
    if (traceCtx.isValid) {
      allProps['traceId'] = traceCtx.traceId;
      allProps['spanId'] = traceCtx.spanId;
    }
    final filteredProps = <String, Object>{};
    for (final entry in allProps.entries) {
      final v = entry.value;
      if (v != null) filteredProps[entry.key] = v;
    }
    emitToOtel(
      severityNumber: severityNumber(event.level),
      severityText: severityText(event.level),
      body: event.message,
      attributes: filteredProps,
    );
  }

  @override
  void emitToOtel({
    required int severityNumber,
    required String severityText,
    required String body,
    required Map<String, Object> attributes,
  }) {
    final logger = _getLogger();
    logger.emit(otel.LogRecord(
      timestamp: DateTime.now(),
      observedTimestamp: DateTime.now(),
      severityNumber: otel.Severity.fromNumber(severityNumber),
      severityText: severityText,
      body: otel.AttributeValue.string(body),
      attributes: otel.Attributes.fromMap(attributes),
    ));
  }

  @override
  TraceContext extractTraceContext() {
    final ctx = otel.Context.root;
    final spanCtx = ctx.span?.spanContext;
    if (spanCtx != null && spanCtx.isValid) {
      return TraceContext(
        traceId: spanCtx.traceId.toString(),
        spanId: spanCtx.spanId.toString(),
      );
    }
    return TraceContext.empty;
  }
}
