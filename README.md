<p align="center">
  <a href="https://pub.dev/packages/purple_logger_otel_sdk">
    <img src="https://img.shields.io/pub/v/purple_logger_otel_sdk?label=pub&color=blue" alt="pub version">
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-AGPL--3.0-blue.svg" alt="license">
  </a>
  <img src="https://img.shields.io/badge/dart-%3E%3D3.2.0-0175C2.svg" alt="Dart SDK">
  <img src="https://img.shields.io/badge/tests-5%20passed-brightgreen.svg" alt="tests">
</p>

<h1 align="center">PurpleLogger OTel SDK Bridge</h1>

<p align="center"><strong>Connect purple_logger to PurpleOTel SDK. Structured logs flow seamlessly into OpenTelemetry with automatic severity mapping and trace correlation.</strong></p>

---

## Features

- **EventLogger integration** — Receives fully assembled `LogEvent` objects directly from purple_logger's provider pipeline, avoiding double allocation
- **Severity mapping** — PurpleLogLevel → OTel SeverityNumber mapping following the [OTel Logs specification](https://opentelemetry.io/docs/specs/otel/logs/data-model/#mapping-severitynumber)
- **Trace correlation** — LogRecords automatically inherit `traceId` and `spanId` from active spans when running inside a trace context
- **Property propagation** — All structured properties (scope properties + caller properties) become OTel attributes
- **Error capturing** — Exceptions and stack traces are attached as `error.type`, `error.message`, and `error.stackTrace` attributes
- **Provider caching** — Logger instances are cached by category name, ensuring a single OTel logger per category

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           purple_logger                                  │
│  • LoggerImpl.log() → LogEvent → ProviderLogger.write(event)            │
│  • Provides: Logger, LoggerProvider, LoggingScope, FilterRuleSet         │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ LogEvent
                                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                     purple_logger_otel (abstraction)                      │
│  • OtelLoggerProvider — abstract provider with logger caching            │
│  • OtelLogger — abstract logger with property merging & trace extraction│
│  • OtelSeverityMapping — PurpleLogLevel → OTel severity mixin            │
│  • TraceContext — vendor‑neutral traceId/spanId value object             │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ extends
                                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                purple_logger_otel_sdk (this package)                      │
│  • PurpleOtelLoggerProvider — concrete bridge to PurpleOTel SDK          │
│  • _PurpleOtelLogger.write(LogEvent) — converts event → OTel LogRecord   │
│  • emitToOtel() — calls SDKLogger.emit() with attributes                 │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ OTel LogRecord
                                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                          purple_otel_sdk                                  │
│  • SDKLoggerProvider, SDKLogger — OTel SDK logger implementation         │
│  • Processors & Exporters — Simple/Batch + Console/OTLP                  │
│  • Resource, Attributes, Severity — OTel data model                      │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ OTLP / console
                                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                     OTel Collector / Backend                              │
│  • Grafana + Tempo + Loki    • Azure Monitor / App Insights              │
│  • Jaeger                    • Datadog                                   │
│  • any OTLP-compatible backend                                            │
└──────────────────────────────────────────────────────────────────────────┘
```

## Installation

```yaml
dependencies:
  purple_logger: ^0.3.0
  purple_logger_otel: ^0.1.0
  purple_logger_otel_sdk: ^0.1.0
  purple_otel_sdk: ^0.1.0
```

```bash
dart pub get
```

## Quick Start

A complete working example that bridges purple_logger logs into OpenTelemetry:

```dart
import 'package:purple_logger/purple_logger.dart';
import 'package:purple_otel_sdk/purple_otel_sdk.dart';
import 'package:purple_logger_otel_sdk/purple_logger_otel_sdk.dart';
import 'package:purple_otel_api/purple_otel_api.dart' show Resource, Attributes;

void main() {
  // 1. Create the SDK logger provider — this is your OTel sink.
  final sdkProvider = SDKLoggerProvider(
    resource: Resource(Attributes.fromMap({'service.name': 'my-service'})),
    processors: [
      SimpleLogRecordProcessor(ConsoleLogRecordExporter()),
    ],
  );

  // 2. Wrap it in the bridge provider.
  final bridgeProvider = PurpleOtelLoggerProvider(otelProvider: sdkProvider);

  // 3. Build the logging pipeline with the bridge as a provider.
  final factory = LoggingBuilder()
    .addProvider(bridgeProvider)
    .build();

  // 4. Use purple_logger as usual — logs flow to OTel automatically.
  final logger = factory.createLogger('order-service');

  logger.info('Order placed', properties: {'orderId': 1042});
  logger.warning('Slow query detected', properties: {
    'query': 'SELECT * FROM orders',
    'durationMs': 1250,
  });
  logger.error('Payment failed', error: PaymentException('timeout'));

  factory.dispose();
}
```

## Data Flow

Every log call follows this path from purple_logger to the OTel backend:

```
logger.info("hello", {properties: {user: "alice"}})
    │
    ▼
LoggerImpl.log(PurpleLogLevel.info, ...)
    │ builds LogEvent with scope properties merged
    │
    ▼
ProviderLogger.write(event)
    │ checks: implements EventLogger? → yes
    │
    ▼
PurpleOtelLogger.write(LogEvent event)
    │ ① merges scopeProperties + properties
    │ ② attaches error info if present
    │ ③ extracts traceId/spanId from OTel context
    │ ④ maps severity via severityNumber()/severityText()
    │ ⑤ calls emitToOtel()
    │
    ▼
emitToOtel(severity, body, attributes)
    │ builds otel.LogRecord → logger.emit()
    │
    ▼
SDKLogger.emit(LogRecord)
    │
    ▼
SimpleLogRecordProcessor / BatchLogRecordProcessor
    │
    ▼
ConsoleLogRecordExporter / OtlpHttpLogRecordExporter
    │
    ▼
OTel Collector (OTLP) or stdout → Grafana, Azure Monitor, Jaeger, ...
```

### Severity Mapping

| PurpleLogLevel | OTel SeverityNumber | OTel severityText |
|:---------------|--------------------:|:------------------|
| `trace`        | 1 (TRACE)           | TRACE             |
| `debug`        | 5 (DEBUG)           | DEBUG             |
| `info`         | 9 (INFO)            | INFO              |
| `warning`      | 13 (WARN)           | WARN              |
| `error`        | 17 (ERROR)          | ERROR             |
| `fatal`        | 21 (FATAL)          | FATAL             |
| `none`         | 0 (UNSPECIFIED)     | _(empty)_         |

This mapping follows the OTel Logs specification and ships with the `purple_logger_otel` abstraction package via the `OtelSeverityMapping` mixin.

## Trace Correlation

When running inside an active trace span, log records automatically carry the `traceId` and `spanId`. This enables one-click navigation from a log line to its parent span in Grafana, Azure Monitor, or Jaeger.

```dart
import 'package:purple_otel_sdk/purple_otel_sdk.dart';
import 'package:purple_logger_otel_sdk/purple_logger_otel_sdk.dart';
import 'package:purple_otel_api/purple_otel_api.dart' show Resource, Attributes, Context;

void main() {
  final sdkProvider = SDKLoggerProvider(
    resource: Resource(Attributes.fromMap({'service.name': 'checkout'})),
    processors: [SimpleLogRecordProcessor(ConsoleLogRecordExporter())],
  );
  final bridgeProvider = PurpleOtelLoggerProvider(otelProvider: sdkProvider);
  final factory = LoggingBuilder().addProvider(bridgeProvider).build();

  final tracerProvider = SDKTracerProvider(
    resource: Resource(Attributes.fromMap({'service.name': 'checkout'})),
    spanProcessors: [SimpleSpanProcessor(ConsoleSpanExporter())],
  );

  final tracer = tracerProvider.get('checkout');

  // Inside this span, every log call is automatically correlated.
  final span = tracer.start('process-checkout');
  final ctx = Context.span(span);
  ctx.run(() {
    final logger = factory.createLogger('checkout');
    logger.info('Payment processed'); // ← carries traceId + spanId
  });

  span.end();
  factory.dispose();
  tracerProvider.shutdown();
}
```

When this log record is exported, the attributes include:

```json
{
  "body": "Payment processed",
  "severityText": "INFO",
  "attributes": {
    "traceId": "0af7651916cd43dd8448eb211c80319c",
    "spanId": "b7ad6b7169203331"
  }
}
```

The bridge extracts trace context via `extractTraceContext()`, which reads from `otel.Context.root.span?.spanContext`. If no span is active, `TraceContext.empty` is returned and no trace attributes are added.

## Complete Setup with OTLP Export

Ship logs to an OTel Collector or any OTLP-compatible backend:

```dart
import 'package:purple_logger/purple_logger.dart';
import 'package:purple_otel_sdk/purple_otel_sdk.dart';
import 'package:purple_logger_otel_sdk/purple_logger_otel_sdk.dart';
import 'package:purple_otel_api/purple_otel_api.dart' show Resource, Attributes;

void main() {
  final otelProvider = SDKLoggerProvider(
    resource: Resource(Attributes.fromMap({
      'service.name': 'my-service',
      'service.version': '1.0.0',
      'deployment.environment': 'production',
    })),
    processors: [
      BatchLogRecordProcessor(
        OtlpHttpLogRecordExporter(
          endpoint: Uri.parse('http://localhost:4318/v1/logs'),
        ),
      ),
    ],
  );

  final bridgeProvider = PurpleOtelLoggerProvider(otelProvider: otelProvider);

  final factory = LoggingBuilder()
    .addProvider(bridgeProvider)
    .setMinimumLevel(PurpleLogLevel.info)
    .build();

  final logger = factory.createLogger('api-gateway');

  // These logs are batched and shipped to your OTel Collector.
  logger.info('Server started', properties: {'port': 8080});
  logger.error('Connection refused', error: SocketException('ECONNREFUSED'));

  // Graceful shutdown flushes pending records.
  factory.dispose();
}
```

For production, prefer `BatchLogRecordProcessor` over `SimpleLogRecordProcessor` to reduce export overhead. During shutdown, `factory.dispose()` calls `PurpleOtelLoggerProvider.dispose()`, which triggers `SDKLoggerProvider.shutdown()` and flushes all pending log records.

## Companion Packages

| Package | Description |
|:--------|:------------|
| [purple_logger](https://pub.dev/packages/purple_logger) | Structured logger with provider pipeline, scopes, filters, and formatters |
| [purple_logger_otel](https://pub.dev/packages/purple_logger_otel) | Vendor-neutral OTel bridge abstractions (zero SDK deps) |
| **purple_logger_otel_sdk** | **This package** — concrete bridge from purple_logger to PurpleOTel SDK |
| [purple_otel_sdk](https://pub.dev/packages/purple_otel_sdk) | OpenTelemetry SDK with logging, tracing, metrics, and OTLP export |

---


## Enterprise Support

This package is developed and maintained by **[PurpleSoft S.r.l.](https://www.purplesoft.io)** — a software house based in Monza, Milano, and Lugano (Switzerland), building production-grade software since 2017.

### We don't just write packages. We build ecosystems.

Our open-source portfolio spans **50+ packages** across the full software stack. If you're using Dart or Flutter at scale, chances are you're already running our code.

| Domain | Packages | Highlights |
|--------|----------|------------|
| **Observability** | 7 | Full OpenTelemetry SDK (traces, logs, metrics), W3C propagation, OTLP export, enterprise structured logger with file rotation |
| **AI & ML Inference** | 15 | ONNX runtime bindings, Google Litert/LiteRT/MediaPipe integration, AI federation engine (Synesis), on-device LLM support |
| **Speech** | 16 | Speech-to-Text (STT) for Android & Windows, Text-to-Speech (TTS) with Kokoro engine across all 6 platforms |
| **Payments** | 2 | SumUp POS terminal integration for Flutter — card-present payments, NFC, receipt printing |
| **Caching** | 2 | High-performance in-memory cache with journaling, Dio HTTP cache interceptor |
| **Code Generation** | 1 | OpenAPI/Swagger → Dart/Flutter client generator |
| **Platform** | 2 | iOS Live Activities, multilingual pluralization engine |

### We solve what others can't

When your project hits a wall — a native API that Flutter can't reach, an ONNX model that won't fit on device, a trace pipeline that drops spans under load, a speech engine that needs custom wake-word detection — our team of elite engineers steps in with solutions that work in production.

### Trusted by 50+ enterprises

Our clients include **ABB, Intesa Sanpaolo, Tenaris, Reply, Aubay, Prometeia, Comune di Milano, FIMAP, Altran, BCC,** and dozens more across banking, manufacturing, energy, and public sector.

### Need the impossible solved?

[Contact PurpleSoft](https://www.purplesoft.io/cerchi-contatti-software-house-a-monza-e-milano/) · [purplesoft.io](https://www.purplesoft.io) · [developers@purplesoft.io](mailto:developers@purplesoft.io) · [+39 0362 148 3978](tel:+3903621483978)## License

AGPL-3.0 — see [LICENSE](LICENSE).


