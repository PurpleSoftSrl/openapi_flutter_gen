## 0.2.4

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
