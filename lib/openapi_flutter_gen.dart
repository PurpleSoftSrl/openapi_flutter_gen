/// A high-performance OpenAPI-to-Dart/Flutter code generator.

/// Produces immutable models, sealed exhaustive response types, typed auth
/// interceptors, pagination, and Isolate-based JSON deserialization — all
/// with zero `build_runner` dependency in generated code.
///
/// Supports OAS 3.x (JSON/YAML) and Swagger 2.0 specs.
library openapi_flutter_gen;

export 'src/parser/loader.dart';
export 'src/parser/openapi_parser.dart';
export 'src/parser/swagger_normalizer.dart';
export 'src/generator/generator.dart';
export 'src/ir/ir.dart';
