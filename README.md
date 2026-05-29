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

---

---

---


---

## Built by PurpleSoft

**[PurpleSoft S.r.l.](https://www.purplesoft.io)** — software house with offices in Monza, Milano, and Lugano (Switzerland). Since 2017.

> We build what doesn't exist yet.

### The sectors we dominate

**Conversational AI & Voice Assistants.** We design and ship end-to-end AI voice platforms — from the physical device (ESP32 with custom Opus codec firmware) to the cloud backend (.NET 10, ASP.NET Core, Blazor Server) to the mobile companion app (Flutter with BLE). Our multi-agent LLM architecture orchestrates 8 specialized agents (conversation, memory, content enrichment, exploration, and more) with a multi-layered memory system spanning graph, episodic, and working memory — including adaptive forgetting, poison detection via z-score outlier analysis, and automatic episodic-to-semantic compression. We deploy DeepSeek V4 for primary inference at 53x lower cost than GPT-4o, with multi-provider fallback across OpenAI, Anthropic, Gemini, and Ollama. Our scientific research pipeline uses a 4-scorer verification chain (NLI dual-label, cross-model consistency, evidence retrieval, hallucination detection) with consensus voting to ensure factual accuracy. We design RAG pipelines with HNSW vector search (1024-dim embeddings), hybrid full-text + semantic RRF, sharded K-means search, and training-free chunk pre-filtering.

**Fintech & Payments.** We build payment orchestration layers that abstract Stripe, SumUp, Nexi, Axerve, PayPal, Google Pay, and Apple Pay behind a single API — plus Bitcoin, Ethereum, and 100+ cryptocurrencies. Our engineers have shipped POS terminal firmware, fiscal receipt systems compliant with Italian *Fattura Elettronica* regulations, and cash register management platforms processing millions of transactions.

**Cybersecurity & Identity.** We ship post-quantum cryptography implementations using NIST-standardized algorithms on .NET 10 (ML-KEM, ML-DSA, SLH-DSA) — the cryptography standard that will replace RSA and ECC. Our authentication infrastructure integrates SPID (Italian public digital identity), OAuth 2.0/OpenID Connect across Google, Apple, Microsoft, Facebook, Instagram, LinkedIn, and GitHub. We build digital signature platforms with PKCS#11 hardware security module support, handling the full envelope lifecycle from document preparation to legally binding execution.

**Artificial Intelligence & On-Device ML.** We deploy ONNX models to phones via custom Dart runtime bindings with GPU acceleration. We integrate Litert and MediaPipe for on-device LLM inference. We build neural text-to-speech engines that run across all 6 Flutter platforms — from Android to Web — and speech recognition systems with Italian dialect support. We design content intelligence pipelines that ingest, enrich via LLM, embed (1024-dim vectors), and serve via hybrid semantic search — at scale: 28,000 items enriched, 30,000 embeddings generated, 14 pipelines with 3 stages each (scrape → enrich → embed). DeepSeek V4 Pro processes content enrichment at a fraction of the cost of GPT-4o.

**Enterprise SaaS & Cloud-Native Architecture.** We architect, build, and operate platforms at enterprise scale. Our .NET 10 monorepo spans 239 C# projects with consistent Azure Pipelines CI/CD, 297 test suites passing, zero build errors. We design multi-engine database abstraction layers (PostgreSQL + pgvector, MySQL, Microsoft SQL Server) with automated schema-to-code generation that produces complete ASP.NET API controllers. Our notification engine handles 6 channels (email, push, SMS, chat, webhook, in-app) with DNS-based email validation and template management. Our audio SDK provides unified TTS/STT across ElevenLabs, DashScope, DeepGram, Whisper, and Windows Speech with Opus/OGG codec support and real-time streaming.

**IoT & Embedded Systems.** We write ESP32 firmware targeting ESP-IDF v5.4 with 21 FreeRTOS tasks, I²S audio pipelines, Opus codec integration, and a 6-state WiFi state machine with validated recovery paths. We build certificate authority infrastructure that generates and manages device TLS certificates with challenge-response verification. We write native Flutter plugins for hardware that doesn't have one yet — from payment terminals to BLE device provisioning to audio codecs.

**Observability & DevOps.** Full-stack observability is the foundation we build our client solutions on. We ship a complete OpenTelemetry SDK for Dart/Flutter (traces, logs, metrics, W3C propagation, OTLP export), enterprise structured logging with file rotation, and auto-instrumentation for HTTP, Dio, and Flutter navigation — all red-team audited with 256 automated tests.

### The technologies we master

Our engineering team works across the full stack — from ESP32 firmware in C to cloud-native backends in C# (.NET 10) to cross-platform mobile apps in Dart/Flutter. We write production code in **C# (.NET 10)**, **Dart**, **TypeScript**, **JavaScript**, **C**, **C++**, **Python**, and **Rust**. Our frameworks of choice are **ASP.NET Core**, **Blazor Server**, **Flutter**, **Angular**, and **React**. Our AI stack spans **DeepSeek**, **OpenAI**, **Anthropic Claude**, **Google Gemini**, **Ollama**, **Microsoft Semantic Kernel**, and **Microsoft Agents.AI**. We operate **Microsoft Azure** (Key Vault, Blob Storage, Resource Manager, IoT Hub, Virtual Machines), deploy on **NGINX**, and manage **PostgreSQL + pgvector**, **MySQL**, **Microsoft SQL Server**, and **ESP-IDF v5.4** at scale. We use **EF Core** with **Npgsql** for data access, **FFmpeg** for audio processing, **LVGL** for embedded displays, and **BLE** for device provisioning. Our CI/CD runs on **Azure Pipelines**.

### Microsoft Partner since 2018 · SumUp Partner · Dell Partner

---

### Trusted by

`ABB` `Intesa Sanpaolo` `Tenaris` `Reply` `Aubay` `Comune di Milano` `BCC` `FIMAP` `Alten` `Altran` `Prometeia` `illimity` `Be Shaping the Future` `DS Group` `NVALUE` `Inoptim` `Docflow` `P&C`

*and 40+ other enterprises across banking, manufacturing, energy, and public sector.*

---

> Your project can't wait. We've solved these exact problems for companies you know.
> Let's solve them for you.

[🌐 **purplesoft.io**](https://www.purplesoft.io) &nbsp;·&nbsp; [📧 **developers@purplesoft.io**](mailto:developers@purplesoft.io) &nbsp;·&nbsp; [📞 **+39 0362 148 3978**](tel:+3903621483978) &nbsp;·&nbsp; [💼 **LinkedIn**](https://www.linkedin.com/company/purplesoft-srl) &nbsp;·&nbsp; [🐙 **GitHub**](https://github.com/purplesoftsrl)

## License

AGPL-3.0 — see [LICENSE](LICENSE).











