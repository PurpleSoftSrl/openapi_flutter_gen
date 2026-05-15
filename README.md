# openapi_flutter_gen

> High-performance OpenAPI-to-Dart/Flutter code generator. Parse your spec once, get a complete, ready-to-use API client with zero `build_runner`, zero code generation at build time.

[![pub.dev](https://img.shields.io/pub/v/openapi_flutter_gen?label=pub.dev&logo=dart&color=0175C2)](https://pub.dev/packages/openapi_flutter_gen)
[![CI](https://github.com/PurpleSoftSrl/openapi_flutter_gen/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/PurpleSoftSrl/openapi_flutter_gen/actions/workflows/ci.yml)
[![Publish](https://github.com/PurpleSoftSrl/openapi_flutter_gen/actions/workflows/publish.yml/badge.svg)](https://github.com/PurpleSoftSrl/openapi_flutter_gen/actions/workflows/publish.yml)
[![Stars](https://img.shields.io/github/stars/PurpleSoftSrl/openapi_flutter_gen?color=yellow)](https://github.com/PurpleSoftSrl/openapi_flutter_gen/stargazers)
[![License](https://img.shields.io/badge/license-AGPL%20v3%20%7C%20Commercial-blue)](LICENSE)
[![tests](https://img.shields.io/badge/tests-36%2F36-brightgreen)](https://github.com/PurpleSoftSrl/openapi_flutter_gen/actions)

---

## Why this exists

Other Dart API client tools (retrofit, chopper, ferry) require `build_runner` to run in YOUR project, every time the spec changes. They generate `.g.dart` files you must commit and maintain.

**openapi_flutter_gen** runs once as a CLI. It produces standalone `.dart` source files — immutable models, typed API services, sealed exhaustive responses, auth interceptors, pagination helpers. Commit them, import them, done.

| | openapi_flutter_gen | retrofit | chopper | ferry |
|---|---|---|---|---|
| Zero build_runner in consumer | ✅ | ❌ | ❌ | ❌ |
| Sealed exhaustive responses | ✅ | ❌ | ❌ | ❌ |
| Immutable models (const) | ✅ | ✅ | ❌ | ✅ |
| Typed auth from spec | ✅ | ❌ | ❌ | ❌ |
| Multipart/FormData | ✅ | ✅ | ✅ | ❌ |
| Pagination helpers | ✅ | ❌ | ❌ | ❌ |
| Isolate JSON deserialization | ✅ | ❌ | ❌ | ❌ |
| Swagger 2.0 support | ✅ | ❌ | ❌ | ❌ |

---

## Install

```bash
dart pub global activate openapi_flutter_gen
```

Or add to your project's `dev_dependencies`:

```yaml
dev_dependencies:
  openapi_flutter_gen: ^0.2.5
```

---

## Run

```bash
openapi_flutter_gen --spec swagger.json --output ./lib/api --package-name my_api
```

Or from a URL:

```bash
openapi_flutter_gen --spec-url https://api.example.com/swagger/v1/swagger.json -o ./lib/api
```

### All flags

```
-s, --spec          Path to OpenAPI spec (JSON or YAML)
-u, --spec-url      URL to OpenAPI spec
-o, --output        Output directory (default: ./generated)
-p, --package-name  Dart package name (default: api_client)
--use-compute       Generate Isolate.run wrappers for JSON deserialization
--no-isolates       Disable parallel generation
-h, --help          Show usage
```

---

## Generated client structure

```
my_api/
├── pubspec.yaml                    # Dio + collection dependencies
├── analysis_options.yaml           # Lint rules
└── lib/
    ├── my_api.dart                 # Barrel export
    └── src/
        ├── models/                 # One file per schema
        │   ├── pet.dart            # Immutable class: fromJson, toJson, copyWith, ==, hashCode
        │   ├── pet_status.dart     # Enum with fromJson/toJson
        │   └── ...
        ├── api/                    # Services + result types
        │   ├── api_client.dart     # Root client with typed service getters
        │   ├── pets_api.dart       # PetsApi: one method per operation
        │   ├── list_pets_result.dart  # Sealed result for each operation
        │   └── ...
        └── core/                   # Support files
            ├── auth.dart           # Typed security (Bearer, ApiKey, OAuth2)
            ├── error_handler.dart  # ApiErrorInterceptor (global + per-call)
            ├── interceptors.dart   # Auth, Retry, Logging
            └── pagination.dart     # Offset + Cursor pagination
```

---

## Generated code walkthrough

### Models — immutable, const, full-featured

Each schema becomes a standalone class with everything you need:

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

  // Deserialization: single hash lookup per field, null-safe
  factory Pet.fromJson(Map<String, dynamic> json) {
    return Pet(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      tag: json['tag'] != null ? json['tag'] as String : null,
      status: json['status'] != null ? PetStatus.fromJson(json['status'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (tag != null) 'tag': tag,
      if (status != null) 'status': status.toJson(),
    };
  }

  Pet copyWith({int? id, String? name, String? tag, PetStatus? status}) {
    if (id == null && name == null && tag == null && status == null) return this;
    return Pet(
      id: id ?? this.id,
      name: name ?? this.name,
      tag: tag ?? this.tag,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Pet && id == other.id && name == other.name && tag == other.tag && status == other.status);

  @override
  int get hashCode => Object.hash(id, name, tag, status);

  @override
  String toString() => 'Pet(id=$id, name=$name, tag=$tag, status=$status)';
}
```

### Enums — string or int-backed

```dart
enum PetStatus {
  available('available'),
  pending('pending'),
  sold('sold');

  const PetStatus(this.value);
  final String value;

  static PetStatus fromJson(String json) =>
      PetStatus.values.firstWhere((e) => e.name == json || e.value == json,
          orElse: () => throw ArgumentError('Unknown PetStatus: $json'));

  String toJson() => value;
}
```

### Sealed union types — oneOf / anyOf

oneOf schemas become sealed class hierarchies with exhaustive pattern matching:

```dart
sealed class PetType {
  const PetType();

  factory PetType.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('petType')) {
      return switch (json['petType'] as String) {
        'dog' => PetTypeDog.fromJson(json),
        'cat' => PetTypeCat.fromJson(json),
        _ => _PetTypeUnknown.fromJson(json),
      };
    }
    try { return PetTypeDog.fromJson(json); } catch (_) {}
    try { return PetTypeCat.fromJson(json); } catch (_) {}
    throw FormatException('Cannot decode PetType', json);
  }
}

class PetTypeDog extends PetType {
  const PetTypeDog(this.value);
  final Dog value;
  factory PetTypeDog.fromJson(Map<String, dynamic> json) => PetTypeDog(Dog.fromJson(json));
  Map<String, dynamic> toJson() => value.toJson();
}

class PetTypeCat extends PetType {
  const PetTypeCat(this.value);
  final Cat value;
  factory PetTypeCat.fromJson(Map<String, dynamic> json) => PetTypeCat(Cat.fromJson(json));
  Map<String, dynamic> toJson() => value.toJson();
}
```

### API services — one method per operation, typed parameters

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
      options: options ?? Options(method: 'GET', extra: extra),
      cancelToken: cancelToken,
    );
    return ListPetsResult.fromResponse(response);
  }

  Future<CreatePetResult> createPet({
    required CreatePetRequest createPetRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? extra,
    Options? options,
  }) async {
    final response = await dio.request(
      '/pets',
      data: createPetRequest.toJson(),
      options: options ?? Options(method: 'POST', extra: extra),
      cancelToken: cancelToken,
    );
    return CreatePetResult.fromResponse(response);
  }
}
```

Path parameters are automatically interpolated:

```dart
Future<GetPetResult> getPet({
    required int petId,
    ...
}) async {
    final response = await dio.request('/pets/$petId', ...);
    ...
}
```

### Sealed result types — every HTTP status code is a typed variant

```dart
sealed class ListPetsResult {
  const ListPetsResult();

  factory ListPetsResult.fromResponse(Response response) {
    return switch (response.statusCode!) {
      200 => ListPetsResultHttp200(
        List<Pet>.generate(response.data.length, (i) => Pet.fromJson((response.data as List)[i]), growable: false),
      ),
      400 => ListPetsResultHttp400(Error.fromJson(response.data as Map<String, dynamic>)),
      _ => ListPetsResultError.fromResponse(response),
    };
  }
}

class ListPetsResultHttp200 extends ListPetsResult {
  const ListPetsResultHttp200(this.data);
  final List<Pet> data;
}

class ListPetsResultHttp400 extends ListPetsResult {
  const ListPetsResultHttp400(this.data);
  final Error data;
}

class ListPetsResultError extends ListPetsResult {
  const ListPetsResultError(this.response);
  final Response<dynamic> response;

  factory ListPetsResultError.fromResponse(Response response) => ListPetsResultError(response);
}
```

---

## Using the generated client

### 1. Import and initialize

```dart
import 'package:my_api/my_api.dart';

final client = ApiClient(
  baseUrl: 'https://api.example.com',
  bearerAuth: BearerAuthSecurity(token: jwt),
  errorHandler: ApiErrorInterceptor(
    onUnauthorized: (_) => logout(),
    onServerError: (_) => showErrorToast(),
  ),
);
```

### 2. Make API calls with exhaustive switch

```dart
final result = await client.pets.listPets(limit: 20);

switch (result) {
  case ListPetsResultHttp200(:final data):
    print('Got ${data.length} pets: ${data.map((p) => p.name).join(", ")}');
  case ListPetsResultHttp400(:final data):
    print('Bad request: ${data.message}');
  case ListPetsResultError(:final response):
    print('HTTP ${response.statusCode}: unexpected error');
}
```

### 3. Create resources

```dart
final result = await client.pets.createPet(
  createPetRequest: CreatePetRequest(
    name: 'Rex',
    status: PetStatus.available,
  ),
);

switch (result) {
  case CreatePetResultHttp201(:final data):
    print('Created pet ${data.id}: ${data.name}');
  case CreatePetResultError(:final response):
    print('Failed: ${response.statusCode}');
}
```

### 4. Upload files (multipart/form-data)

Multipart endpoints automatically generate `FormData` — no manual construction needed:

```dart
final result = await client.mediaManager.addOrUpdateMedia(
  culture: 'it',
  bodyMultipartFormData: AddOrUpdateMediaBodyMultipartFormData(
    mediaFile: imageBytes,     // Uint8List → MultipartFile.fromBytes automatically
    contentId: '12345',
    contentTypeId: 'image',
  ),
);
```

### 5. Download binary files

Binary responses use `ResponseType.bytes` automatically:

```dart
final result = await client.mediaManager.getMedia(mediaId: 'abc');
switch (result) {
  case GetMediaResultHttp200(:final data):
    // data is Uint8List
    await File('downloaded.pdf').writeAsBytes(data);
}
```

### 6. Error handling — global + per-call

Global error handler catches all calls:

```dart
final client = ApiClient(
  errorHandler: ApiErrorInterceptor(
    onUnauthorized: (_) => redirectToLogin(),
    onServerError: (_) => reportCrash(),
  ),
);
```

Per-call override with chain or skip:

```dart
// Chain: per-call runs first, then global
await client.pets.deletePet(
  petId: 123,
  extra: {
    'perCallErrorHandler': ApiErrorInterceptor(
      onNotFound: (_) => showToast('Already deleted'),
    ),
  },
);

// Skip global — only this handler fires
await client.pets.deletePet(
  petId: 123,
  extra: {
    'perCallErrorHandler': ApiErrorInterceptor(
      skipGlobal: true,
      onNotFound: (_) => showToast('Already deleted'),
    ),
  },
);
```

### 7. Pagination — forEach / toList

Offset-based:

```dart
final result = await client.pets.listPets(limit: 50);
switch (result) {
  case ListPetsResultHttp200(:final data):
    await data.forEach((pet) async => await processPet(pet));
    final all = await data.toList(); // collects all pages
}
```

### 8. Dio cache integration

Add `dio_mcache` for transparent caching:

```dart
import 'package:dio_mcache/dio_mcache.dart';

final client = ApiClient(
  baseUrl: 'https://api.example.com',
  bearerAuth: BearerAuthSecurity(token: jwt),
  dio: Dio()..interceptors.add(DioCacheInterceptor(
    options: DioCacheOptions(expiration: const Duration(minutes: 5)),
  )),
);
// All API calls are now cached automatically
```

### 9. Auth — token provider for dynamic refresh

```dart
final client = ApiClient(
  bearerAuth: BearerAuthSecurity(
    tokenProvider: () async {
      final stored = await secureStorage.read('jwt');
      if (stored != null) return stored;
      return await refreshToken();
    },
  ),
);
```

### 10. Custom Dio instance

```dart
final client = ApiClient(
  dio: Dio(BaseOptions(
    baseUrl: 'https://api.example.com',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ))..interceptors.addAll([
    DioCacheInterceptor(options: DioCacheOptions(expiration: const Duration(minutes: 5))),
    LoggingInterceptor(),
  ]),
);
```

---

## Compute mode — Isolate-based JSON deserialization

For large API responses, JSON deserialization can block the main isolate. Use `--use-compute` to generate `Isolate.run` wrappers:

```bash
openapi_flutter_gen --spec swagger.json --use-compute
```

The generated service methods wrap deserialization in an isolate:

```dart
Future<ListPetsResult> listPets({...}) async {
  final response = await dio.request('/pets', ...);
  // Deserialization runs in a separate isolate — main thread stays responsive
  final statusCode = response.statusCode ?? 0;
  final data = response.data;
  return Isolate.run(() => deserializeListPets((statusCode: statusCode, data: data)));
}
```

---

## Supported specifications

| Format | Version | Tested with |
|---|---|---|
| OpenAPI 3.x (JSON) | 3.0.x | petstore.json (14 schemas) |
| OpenAPI 3.x (YAML) | 3.1.x | train-travel OpenAPI (47 schemas) |
| Swagger 2.0 (JSON) | 2.0 | petstore.swagger.io (16 schemas) |
| Production API (JSON) | 3.0 | 927 schemas, 605 operations, 0 issues |

---

## Features

- **OAS 3.x + Swagger 2.0** — JSON + YAML, full `$ref` resolution, oneOf/anyOf/allOf, discriminators, inline schema extraction at any nesting depth
- **Sealed exhaustive responses** — every HTTP status code maps to a typed variant; switch statements are checked for exhaustiveness at compile time
- **Immutable models** — `const` constructors, `copyWith` with zero-allocation fast path, structural `==`/`hashCode`, `toString`
- **Typed auth** — Bearer, ApiKey, OAuth2, OpenID Connect generated from spec's `securitySchemes`; static token or dynamic `tokenProvider`
- **Per-request auth override** — every API method accepts `options` and `extra` parameters, enabling per-call cache control, error handling, and more
- **Multipart/FormData** — binary fields automatically use `MultipartFile.fromBytes` in `toFormData()`; string/int fields map to form fields
- **Error handling** — global `ApiErrorInterceptor` with callbacks per status code; per-call overrides with chain/skip semantics
- **Pagination** — offset-based and cursor-based `PaginatedResponse<T>` with `forEach` and `toList` extensions
- **Dio-based** — uses Dio for HTTP; supports custom `Dio` instances, interceptors, and base URL
- **Compute mode** — `--use-compute` wraps heavy JSON deserialization in `Isolate.run`, keeping the main isolate responsive
- **Parallel generation** — file writing distributed across isolates for large specs
- **Zero build_runner** — no code generation at build time; no `.g.dart` files; just import and use

---

## Architecture

```
Spec (JSON/YAML)
    │
    ▼
Loader ──► SwaggerNormalizer (Swagger 2.0 → OAS 3.x)
    │
    ▼
OpenApiSpecParser
    ├── $ref resolution
    ├── inline schema extraction (recursive, any depth)
    └── IR construction (IrSchema, IrOperation, IrApiDocument)
    │
    ▼
CodeGenerator (parallel via Isolate.spawn)
    ├── ModelGenerator     (IrObjectSchema → class, IrEnumSchema → enum, IrUnionSchema → sealed class)
    ├── ApiGenerator       (IrOperation → service method + sealed result type)
    └── SupportGenerator   (auth, error handler, interceptors, pagination, pubspec, barrel)
    │
    ▼
.dart files → import and use
```

---

## Contributing

```bash
dart test  # 36 tests, 3 spec formats, compute + normal mode
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
