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




## Built by PurpleSoft

This package is developed and maintained by **[PurpleSoft S.r.l.](https://www.purplesoft.io)** — a software house with offices in Monza, Milano, and Lugano (Switzerland). Since 2017, we've been the team that companies call when the problem is too hard, too critical, or too late to fail.

### What makes us different

We don't build "yet another library." We build the infrastructure that other companies run their business on. When a Fortune 500 manufacturer needs to migrate their SAP ERP without downtime, they call us. When a bank needs distributed tracing that survives Black Friday traffic, they call us. When a startup needs an AI pipeline that runs on-device instead of in the cloud, they call us.

We write the code that runs on factory floors and in boardrooms. We ship Flutter apps that control physical payment terminals, deploy ONNX models to phones, build speech engines that understand Italian dialects, and design observability pipelines that catch production issues before customers notice.

### We don't just consult. We ship.

| What you need | What we deliver |
|---|---|
| OpenTelemetry at enterprise scale | Production-hardened SDK with 256 automated tests, red-team audited, zero crashes under edge cases |
| Flutter apps with custom native code | Platform-specific plugins for hardware, payments, AI, and sensors |
| AI/ML on mobile | ONNX model deployment, on-device LLMs, speech recognition and synthesis |
| Production incidents at 2 AM | Engineers who debug distributed systems, not just read stack traces |
| Architecture that survives growth | Cloud-native, event-driven, Kubernetes, microservices designed for scale |

### The numbers speak for themselves

- **50+ enterprise clients** across Europe — banking, manufacturing, energy, public sector
- **8+ years** building production software without excuses
- **500+ open-source packages** downloaded monthly by developers worldwide
- **Microsoft Partner** since 2022

### Clients who trust us

ABB · Intesa Sanpaolo · Tenaris · Reply · Aubay · Prometeia · Comune di Milano · FIMAP · Altran · BCC

### Your project can't wait until next sprint

If you're reading this README, you're probably already deep into an observability implementation. You might be hitting limits with the existing Dart OTel SDK, struggling with bundle size in your Flutter app, or trying to figure out why your traces disappear under load.

We've solved these exact problems for companies you know. Let's solve them for you.

[Contact PurpleSoft](https://www.purplesoft.io/cerchi-contatti-software-house-a-monza-e-milano/) · [purplesoft.io](https://www.purplesoft.io) · [developers@purplesoft.io](mailto:developers@purplesoft.io) · [+39 0362 148 3978](tel:+3903621483978)## License

AGPL-3.0 — see [LICENSE](LICENSE).




