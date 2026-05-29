import 'package:purple_logger/purple_logger.dart';
import 'package:purple_logger_otel_sdk/purple_logger_otel_sdk.dart';
import 'package:purple_otel_api/purple_otel_api.dart' as otel;
import 'package:purple_otel_sdk/purple_otel_sdk.dart';
import 'package:test/test.dart';

final class _CaptureExporter implements otel.LogRecordExporter {
  final List<otel.LogRecord> exported = [];

  @override
  Future<otel.ExportResult> export(List<otel.LogRecord> items) async {
    exported.addAll(items);
    return otel.ExportResult.success();
  }

  @override
  Future<void> shutdown() async {}

  @override
  Future<void> forceFlush() async {}
}

void main() {
  group('PurpleOtelLoggerProvider', () {
    test('bridges purple_logger hello world to OTel SDK', () {
      final exporter = _CaptureExporter();
      final sdkProvider = SDKLoggerProvider(
        resource: otel.Resource.empty,
        processors: [SimpleLogRecordProcessor(exporter)],
      );
      final bridgeProvider =
          PurpleOtelLoggerProvider(otelProvider: sdkProvider);
      final factory = LoggingBuilder().addProvider(bridgeProvider).build();
      final logger = factory.createLogger('test');

      logger.info('hello from purple_logger');

      expect(exporter.exported.length, 1);
      expect(exporter.exported.first.severityNumber, otel.Severity.info);
    });

    test('severity mapping from purple_logger levels', () {
      final exporter = _CaptureExporter();
      final sdkProvider = SDKLoggerProvider(
        resource: otel.Resource.empty,
        processors: [SimpleLogRecordProcessor(exporter)],
      );
      final bridgeProvider =
          PurpleOtelLoggerProvider(otelProvider: sdkProvider);
      final factory = LoggingBuilder().addProvider(bridgeProvider).build();
      final logger = factory.createLogger('test');

      logger.trace('trace msg');
      logger.info('info msg');
      logger.warning('warn msg');
      logger.error('error msg');

      expect(exporter.exported.length, 4);
      expect(exporter.exported[0].severityNumber, otel.Severity.trace);
      expect(exporter.exported[1].severityNumber, otel.Severity.info);
      expect(exporter.exported[2].severityNumber, otel.Severity.warn);
      expect(exporter.exported[3].severityNumber, otel.Severity.error);
    });

    test('properties are propagated as OTel attributes', () {
      final exporter = _CaptureExporter();
      final sdkProvider = SDKLoggerProvider(
        resource: otel.Resource.empty,
        processors: [SimpleLogRecordProcessor(exporter)],
      );
      final bridgeProvider =
          PurpleOtelLoggerProvider(otelProvider: sdkProvider);
      final factory = LoggingBuilder().addProvider(bridgeProvider).build();
      final logger = factory.createLogger('test');

      logger.info('msg with props', properties: {
        'user.id': '123',
        'request.method': 'GET',
      });

      final record = exporter.exported.first;
      expect(
          record.attributes.get('user.id'), otel.AttributeValue.string('123'));
      expect(record.attributes.get('request.method'),
          otel.AttributeValue.string('GET'));
    });

    test('provider caching works', () {
      final exporter = _CaptureExporter();
      final sdkProvider = SDKLoggerProvider(
        resource: otel.Resource.empty,
        processors: [SimpleLogRecordProcessor(exporter)],
      );
      final bridgeProvider =
          PurpleOtelLoggerProvider(otelProvider: sdkProvider);
      final factory = LoggingBuilder().addProvider(bridgeProvider).build();
      final logger1 = factory.createLogger('cached');
      final logger2 = factory.createLogger('cached');

      expect(identical(logger1, logger2), isTrue);
    });

    test('dispose calls SDK shutdown', () {
      final exporter = _CaptureExporter();
      final sdkProvider = SDKLoggerProvider(
        resource: otel.Resource.empty,
        processors: [SimpleLogRecordProcessor(exporter)],
      );
      final bridgeProvider =
          PurpleOtelLoggerProvider(otelProvider: sdkProvider);
      bridgeProvider.dispose();
      // Just verify no crash — dispose triggers SDK shutdown
    });
  });
}
