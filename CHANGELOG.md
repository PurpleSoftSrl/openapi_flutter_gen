## 0.1.1

- Swagger 2.0 / OpenAPI 2.0 support via SwaggerNormalizer (definitions → components/schemas, host+basePath → servers, body params → requestBody, securityDefinitions → securitySchemes)
- 2 new Swagger 2.0 integration tests using official petstore.swagger.io spec

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
