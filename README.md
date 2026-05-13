# openapi_flutter_gen

> High-performance OpenAPI-to-Dart/Flutter code generator. Produces immutable models, sealed-class exhaustive response types, typed auth, multipart FormData, pagination — all with zero build_runner dependency in generated code.

[![pub.dev](https://img.shields.io/pub/v/openapi_flutter_gen?label=pub.dev&logo=dart&color=0175C2)](https://pub.dev/packages/openapi_flutter_gen)
[![CI](https://github.com/PurpleSoftSrl/openapi_flutter_gen/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/PurpleSoftSrl/openapi_flutter_gen/actions/workflows/ci.yml)
[![Publish](https://github.com/PurpleSoftSrl/openapi_flutter_gen/actions/workflows/publish.yml/badge.svg)](https://github.com/PurpleSoftSrl/openapi_flutter_gen/actions/workflows/publish.yml)
[![Stars](https://img.shields.io/github/stars/PurpleSoftSrl/openapi_flutter_gen?color=yellow)](https://github.com/PurpleSoftSrl/openapi_flutter_gen/stargazers)
[![License](https://img.shields.io/badge/license-AGPL%20v3%20%7C%20Commercial-blue)](LICENSE)
[![tests](https://img.shields.io/badge/tests-passing-brightgreen)](https://github.com/PurpleSoftSrl/openapi_flutter_gen/actions)

Unlike other Dart/Flutter API clients (retrofit, chopper, ferry) that require build_runner at the consumer side, **openapi_flutter_gen** runs once as a CLI tool and produces ready-to-use Dart source files. No code generation in your CI. No generated `.g.dart` files to commit. Just pure Dart.

---

## Why openapi_flutter_gen?

| | openapi_flutter_gen | retrofit | chopper | ferry |
|---|---|---|---|---|
| Zero build_runner in consumer | ✅ | ❌ | ❌ | ❌ |
| Sealed exhaustive responses | ✅ | ❌ | ❌ | ❌ |
| Immutable models (const) | ✅ | ✅ | ❌ | ✅ |
| Typed auth from spec | ✅ | ❌ | ❌ | ❌ |
| Multipart/FormData | ✅ | ✅ | ✅ | ❌ |
| Pagination helpers | ✅ | ❌ | ❌ | ❌ |
| Isolate JSON deserialization | ✅ | ❌ | ❌ | ❌ |
| Parallel generation | ✅ | ❌ | ❌ | ❌ |
| copyWith/==/hashCode | ✅ | ❌ | ❌ | ✅ |

---

## Install

```bash
dart pub global activate openapi_flutter_gen
```

---

## CLI usage

```bash
openapi_flutter_gen --spec swagger.json --output ./lib/generated --package-name my_api
```

### All flags

```
Options:
  -s, --spec          Path to OpenAPI spec (JSON or YAML)
  -u, --spec-url      URL to OpenAPI spec
  -o, --output        Output directory (default: ./generated)
  -p, --package-name  Dart package name (default: api_client)
  --use-compute       Generate Isolate.run wrappers for JSON deserialization
  --no-isolates       Disable parallel generation
  -h, --help          Show usage
```

---

## Generated output structure

```
generated/
└── my_api/
    ├── pubspec.yaml
    ├── analysis_options.yaml
    └── lib/
        ├── my_api.dart                  # Barrel export
        └── src/
            ├── models/
            │   ├── pet.dart             # Pet model
            │   ├── user.dart            # User model
            │   ├── order.dart           # Order model
            │   ├── category.dart        # Category model
            │   ├── address.dart         # Address model
            │   ├── pet_status.dart      # PetStatus enum
            │   ├── user_role.dart       # UserRole enum
            │   ├── order_status.dart    # OrderStatus enum
            │   ├── error.dart           # Error model
            │   └── ...
            ├── api/
            │   ├── api_client.dart      # Root client with typed services
            │   ├── pets_api.dart        # PetsApi service
            │   ├── users_api.dart       # UsersApi service
            │   ├── orders_api.dart      # OrdersApi service
            │   ├── list_pets_result.dart # Sealed result for each operation
            │   └── ...
            └── core/
                ├── auth.dart            # Typed auth security classes
                ├── error_handler.dart   # ApiErrorInterceptor
                ├── interceptors.dart    # Auth, Retry, Logging interceptors
                └── pagination.dart      # Offset + cursor pagination helpers
```

---

## Code examples

### Input — OpenAPI 3.x spec

```json
{
  "openapi": "3.0.3",
  "paths": {
    "/pets": {
      "get": {
        "operationId": "listPets",
        "tags": ["pets"],
        "responses": {
          "200": {
            "content": {
              "application/json": {
                "schema": {
                  "type": "array",
                  "items": { "$ref": "#/components/schemas/Pet" }
                }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "Pet": {
        "type": "object",
        "required": ["id", "name"],
        "properties": {
          "id": { "type": "integer", "format": "int64" },
          "name": { "type": "string" },
          "tag": { "type": "string" },
          "status": { "$ref": "#/components/schemas/PetStatus" }
        }
      },
      "PetStatus": {
        "type": "string",
        "enum": ["available", "pending", "sold"]
      }
    }
  }
}
```

### Generated model

```dart
class Pet {
  const Pet({
    required this.id,
    required this.name,
    this.tag,
    this.status,
  });

  final int id;
  final String name;
  final String? tag;
  final PetStatus? status;

  factory Pet.fromJson(Map<String, dynamic> json) {
    return Pet(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      tag: json['tag'] != null
          ? json['tag'] as String
          : null,
      status: json['status'] != null
          ? PetStatus.fromJson(json['status'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() { ... }
  Pet copyWith({ ... }) { ... }

  @override
  bool operator ==(Object other) { ... }
  @override
  int get hashCode => Object.hash(id, name, tag, status);
  @override
  String toString() => 'Pet(id=$id, name=$name, tag=$tag, status=$status)';
}
```

### Generated API

```dart
class PetsApi {
  const PetsApi({required this.dio, this.baseUrl});
  final Dio dio;
  final String? baseUrl;

  Future<ListPetsResult> listPets({
    int? limit,
    PetStatus? status,
    CancelToken? cancelToken,
    Map<String, dynamic>? extra,
    Options? options,
  }) async {
    final reqQueryParams = <String, dynamic>{};
    if (limit != null) reqQueryParams['limit'] = limit.toString();
    if (status != null) reqQueryParams['status'] = status.toJson().toString();

    final response = await dio.request(
      '/pets',
      queryParameters: reqQueryParams.isNotEmpty ? reqQueryParams : null,
      options: options ?? Options(
        method: 'GET',
        headers: null,
        extra: extra,
      ),
      cancelToken: cancelToken,
    );

    return ListPetsResult.fromResponse(response);
  }
}
```

### Usage

```dart
final client = ApiClient(
  baseUrl: 'https://api.example.com',
  bearerAuth: BearerAuthSecurity(token: jwt),
  errorHandler: ApiErrorInterceptor(onUnauthorized: (_) => logout()),
);

final result = await client.pets.listPets();

switch (result) {
  case ListPetsResultHttp200(:final data):
    print('Got ${data.length} pets');
  case ListPetsResultError(:final response):
    print('Error: ${response.statusCode}');
}
```

---

## Features

- **OAS 3.x support** — JSON + YAML, full `$ref` resolution, oneOf/anyOf/allOf, discriminators
- **Sealed class exhaustive response types** — every HTTP status code is a typed variant
- **Typed auth** — Bearer, ApiKey, OAuth2, OpenID Connect generated from spec
- **Multipart/FormData** — binary fields automatically use `MultipartFile.fromBytes()`
- **Centralized error handling** — global + per-call with chain/skip via `ApiErrorInterceptor`
- **Pagination** — offset and cursor with `forEach`/`toList` extensions
- **Isolate deserialization** — `--use-compute` wraps heavy JSON in `Isolate.run`
- **Immutable models** — const constructors, `copyWith`, structural equality
- **Streaming** — binary downloads use `ResponseType.bytes`
- **Parallel generation** — isolates for file writing
- **Zero build_runner dependency** — no build_runner, no freezed, no retrofit in generated code

---

## Architecture

```
OpenAPI Spec (JSON/YAML)
        │
        ▼
      Loader              loadSpec / loadSpecFromUrl
        │
        ▼
   OpenApiSpecParser      Parse → resolve $ref → build IR
        │
        ▼
    IrApiDocument         schemas, operations, operationsByTag, servers, securitySchemes
        │
        ▼
   CodeGenerator
   ├── ModelGenerator     IrSchema → Dart class/enum/sealed class
   ├── ApiGenerator       IrOperation → service methods + sealed result types
   └── SupportGenerator   auth, error handler, interceptors, pagination, pubspec, barrel
        │
        ▼
    .dart files           Ready to use — import and go
```

---

## Contributing

```bash
dart test
```

---

## License

**Dual-licensed.**

### Open Source — GNU AGPL v3

You can use, modify, and distribute this software freely under the terms of the
[GNU Affero General Public License v3](LICENSE). This includes the network-use
clause: if you modify openapi_flutter_gen and run it as part of a network service (SaaS),
you must make your modifications available to users of that service.

### Commercial License

If the AGPL does not fit your business model, a **commercial license** is available.

**What you get:**
- Full rights to use openapi_flutter_gen in proprietary, closed-source applications
- No obligation to disclose your source code or modifications
- No network-use copyleft restrictions
- Priority email support
- Indemnification

[Contact us](mailto:developers@purplesoft.io) for pricing and terms.
