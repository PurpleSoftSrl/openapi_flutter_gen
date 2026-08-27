## 0.2.11

- Fix: auth interceptors stamp the Authorization header only for a non-empty token (previously a bare `Bearer ` was sent for an empty token).
- Fix: enum fields in multipart form data serialize to their wire value (`.toJson()`) instead of `EnumType.name`.

## 0.2.10

- Rewrite README comparison table: replaced non-OpenAPI tools (retrofit, chopper, ferry) with real pub.dev competitors (swagger_dart_code_generator, swagger_parser, openapi_generator, space_gen, openapi_spec), verified by source code analysis
- Add "Standalone CLI" row to comparison table
- Update install instructions to ^0.2.10

## 0.2.9

- Bump dev dependencies: `lints` ^6.1.0, `test` ^1.31.2
- Restore version constraints on all dependencies for pub.dev compliance

## 0.2.8

- Fix primitive list/map `fromJson` deserialization: emit `(expr as List).cast<T>()` and `(expr as Map).cast<K, V>()` instead of a direct `expr as List<T>` / `as Map<K, V>` cast. A decoded JSON array/object is always `List<dynamic>` / `Map<String, dynamic>` at runtime, so the direct cast threw `type 'List<dynamic>' is not a subtype of type 'List<String>'` — crashing deserialization of any model with a primitive array (e.g. a login response `roles` field, breaking authentication). Now consistent with the `.cast<T>()` already used in `type_utils.dart`.

## 0.2.7

- Fix barrel file generation: export ALL model classes, API service files, and result type files instead of only 5 hardcoded core exports
- Fix OpenAPI 3.1 nullable type array parsing: `["null","string"]` format now correctly resolves to nullable string instead of `Object?`
- Add `_extractType()` method to handle type arrays by extracting the first non-null type
- Add nullable detection from type arrays in `_isSchemaNullable()` for OAS 3.1 spec compatibility

## 0.2.6

- Add dartdoc from OpenAPI spec `description` fields on generated classes
- Add dartdoc on `fromJson` factory constructors
- Fix union variant `toJson` return type (Map wrapper)

## 0.2.5

- Auto-format generated code with `dart format` after generation
- Fix `[]` brackets in schema/parameter names (OAS 3.1 compatibility)
- Fix `String??` double-nullable in generated method signatures
- Fix missing inline schema files (IrPrimitiveSchema, IrListSchema)
- Fix inline enum/object extraction from nested schemas
- Fix `List.generate` strict-cast: add `(expr as List).length` cast
- Fix `Response<dynamic>` → `Response` raw type warnings
- Fix `dio.request` → `dio.request<Map<String, dynamic>>` type param
- Fix duplicate schema naming (Post400Response → Post400Response1)
- Fix `requestBody` with empty schema generating invalid code

- Add dartdoc documentation to all public API (20%+ coverage)
- Shorten pubspec description for pub.dev scoring
- Add example/ directory with usage sample

## 0.2.3

- Update README with correct version references

## 0.2.2

- Generated pubspec uses pinned versions (dio: ^5.7.0, collection: ^1.19.0) instead of any

## 0.2.1

- Test fixtures included in repo for CI compatibility
- Fix test file paths for GitHub Actions

## 0.2.0

- Full OAS 3.1 YAML support (tested with train-travel OpenAPI)
- Swagger 2.0 support via SwaggerNormalizer (definitions → components/schemas, host+basePath → servers, body params → requestBody, securityDefinitions → securitySchemes)
- Inline schema extraction: inline objects, enums, oneOf items from properties, allOf items, array items
- Inline schema extraction at 3+ nesting levels with recursive extraction
- $ref resolution for extracted schemas added to _doc post-extraction
- Union model generator: variant classes at top level (not nested), variant naming without shadowing import names
- Empty models generate `const Foo();` not invalid `const Foo({});`
- Model imports use lowercase paths (macOS/Linux case-sensitivity)
- Remove redundant allOfRef imports from generated models
- Compute/Isolate mode: 0 issues on all 3 specs
- 36 tests: parser, model generation, API generation, full pipeline, Swagger 2.0, train-travel OAS 3.1, compute mode
- All generated clients compile with exit code 0 (0 errors, 0 warnings, 0 info)
- GitHub Actions CI + OIDC publish workflows

## 0.1.1

- Swagger 2.0 / OpenAPI 2.0 support via SwaggerNormalizer
- 2 Swagger 2.0 integration tests using official petstore.swagger.io spec

## 0.1.0

- Initial release
- OpenAPI 3.x JSON/YAML parser with full $ref resolution
- Immutable model generation: fromJson/toJson/copyWith/==/hashCode
- Dio-based API service generation with sealed exhaustive response types
- Typed auth generation (Bearer, ApiKey, OAuth2)
- Multipart/FormData support with MultipartFile.fromBytes
- Centralized error handling via ApiErrorInterceptor
- Pagination helpers (offset + cursor)
- --use-compute flag for Isolate.run JSON deserialization
- Parallel generation via Isolate.spawn
- Zero build_runner dependency in generated code
