## 0.1.3


## 0.1.2


## 0.1.0

- Initial release
- Bridges purple_logger LogEvents to PurpleOTel LogRecords
- Automatic severity mapping (purple_logger levels → OTel SeverityNumber)
- Trace correlation via active span context
- Structured property propagation as OTel attributes
- Error and stack trace capture as exception.type/message/stacktrace
- Provider-level logger caching by category
