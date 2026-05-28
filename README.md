# PurpleLogger OTel SDK Bridge

[![Pub Version](https://img.shields.io/pub/v/purple_logger_otel_sdk.svg)](https://pub.dev/packages/purple_logger_otel_sdk)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

Bridge that connects [purple_logger](https://pub.dev/packages/purple_logger) to [PurpleOTel SDK](https://pub.dev/packages/purple_otel_sdk) — structured logs become OpenTelemetry LogRecords with trace correlation.

## Features

- **EventLogger integration** — receives `LogEvent` objects directly from purple_logger's provider pipeline
- **Severity mapping** — purple_logger levels → OTel SeverityNumber (1-24)
- **Trace correlation** — LogRecords automatically inherit traceId/spanId from active spans
- **Property propagation** — all structured properties (scope + caller) become OTel attributes
- **Error capturing** — exceptions and stack traces as `exception.type`, `exception.message`, `exception.stacktrace`
- **Provider caching** — logger instances cached by category name

## Quick Start

```dart
import 'package:purple_logger/purple_logger.dart';
import 'package:purple_otel_sdk/purple_otel_sdk.dart';
import 'package:purple_logger_otel_sdk/purple_logger_otel_sdk.dart';

void main() {
  // 1. Create OTel SDK logger provider
  final otelProvider = SDKLoggerProvider(
    resource: Resource(Attributes.fromMap({'service.name': 'my-app'})),
    processors: [SimpleLogRecordProcessor(ConsoleLogRecordExporter())],
  );

  // 2. Wire through the bridge
  final factory = LoggingBuilder()
    .addProvider(PurpleOtelLoggerProvider(otelProvider: otelProvider))
    .build();

  // 3. Use purple_logger as usual — logs flow to OTel automatically
  final logger = factory.createLogger('order-service');
  logger.info('Order placed', properties: {'orderId': 1042});
}
```

## Data Flow

```
purple_logger.info("message", {properties})
    ↓
LoggerImpl.log() → LogEvent
    ↓
PurpleOtelLoggerProvider (EventLogger)
    ↓
SDKLogger.emit(LogRecord) → processors → OTLP exporter
    ↓
OTel Collector (Jaeger, Tempo, Grafana, Azure Monitor)
```

## License

Apache-2.0 — see [LICENSE](LICENSE).
