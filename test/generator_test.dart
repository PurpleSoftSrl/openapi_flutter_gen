import 'dart:convert';
import 'dart:io';

import 'package:openapi_flutter_gen/src/parser/loader.dart';
import 'package:openapi_flutter_gen/src/parser/openapi_parser.dart';
import 'package:openapi_flutter_gen/src/parser/swagger_normalizer.dart';
import 'package:openapi_flutter_gen/src/ir/ir.dart';
import 'package:openapi_flutter_gen/src/generator/generator.dart';
import 'package:openapi_flutter_gen/src/generator/dart/model_generator.dart';
import 'package:openapi_flutter_gen/src/generator/dart/api_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _keepTemp = Platform.environment['KEEP_TEST_OUTPUT'] == '1';

void _cleanupDir(Directory d) {
  if (!_keepTemp) {
    d.deleteSync(recursive: true);
  } else {
    print('  📁 KEPT: ${d.path}');
  }
}

final String petstorePath = p.normalize(
  p.join(p.current, 'test', 'fixtures', 'petstore.json'),
);

void main() {
  late Map<String, dynamic> petstoreJson;
  late IrApiDocument apiDoc;

  setUpAll(() async {
    petstoreJson = json.decode(await File(petstorePath).readAsString())
        as Map<String, dynamic>;
    final parser = OpenApiSpecParser(petstoreJson);
    apiDoc = parser.parse();
  });

  group('OpenApiSpecParser', () {
    test('parses petstore.json and has expected schemas', () {
      final schemaNames = apiDoc.schemas.keys.toSet();
      expect(schemaNames, contains('Pet'));
      expect(schemaNames, contains('User'));
      expect(schemaNames, contains('Order'));
      expect(schemaNames, contains('Error'));
      expect(schemaNames, contains('PetStatus'));
      expect(schemaNames, contains('UserRole'));
      expect(schemaNames, contains('OrderStatus'));
      expect(schemaNames, contains('Category'));
      expect(schemaNames, contains('Address'));
      expect(schemaNames, contains('CreatePetRequest'));
      expect(schemaNames, contains('CreateUserRequest'));
      expect(schemaNames, contains('CreateOrderRequest'));
      expect(schemaNames, contains('UpdatePetRequest'));
      expect(schemaNames, contains('ErrorDetail'));
    });

    test('parses petstore.json and has expected operations', () {
      final operationIds =
          apiDoc.operations.map((op) => op.operationId).toSet();
      expect(operationIds, contains('listPets'));
      expect(operationIds, contains('createPet'));
      expect(operationIds, contains('getPet'));
      expect(operationIds, contains('updatePet'));
      expect(operationIds, contains('deletePet'));
      expect(operationIds, contains('createUser'));
      expect(operationIds, contains('getUser'));
      expect(operationIds, contains('placeOrder'));
      expect(operationIds, contains('listOrders'));
    });

    test('parses petstore.json and has expected tags', () {
      final tags = <String>{};
      for (final op in apiDoc.operations) {
        tags.addAll(op.tags);
      }
      expect(tags, contains('pets'));
      expect(tags, contains('users'));
      expect(tags, contains('orders'));
    });

    test('parses info correctly', () {
      expect(apiDoc.info.title, equals('Petstore API'));
      expect(apiDoc.info.version, equals('1.0.0'));
    });

    test('parses servers correctly', () {
      expect(apiDoc.servers.length, greaterThan(0));
      expect(apiDoc.servers.first.url,
          equals('https://petstore.example.com/api/v1'));
    });

    test('parses security schemes', () {
      expect(apiDoc.securitySchemes, contains('bearerAuth'));
      final scheme = apiDoc.securitySchemes['bearerAuth']!;
      expect(scheme.type, equals('http'));
      expect(scheme.scheme, equals('bearer'));
    });

    test('parses Pet schema with all properties', () {
      final pet = apiDoc.schemas['Pet']!;
      expect(pet, isA<IrObjectSchema>());
      final petSchema = pet as IrObjectSchema;
      final propNames = petSchema.properties.map((p) => p.name).toSet();
      expect(propNames, contains('id'));
      expect(propNames, contains('name'));
      expect(propNames, contains('tag'));
      expect(propNames, contains('status'));
      expect(propNames, contains('category'));
      expect(propNames, contains('photoUrls'));
      expect(propNames, contains('createdAt'));
    });

    test('PetStatus is an enum with correct values', () {
      final ps = apiDoc.schemas['PetStatus']!;
      expect(ps, isA<IrEnumSchema>());
      final enumSchema = ps as IrEnumSchema;
      final valueNames = enumSchema.values.map((v) => v.name).toSet();
      expect(valueNames, contains('available'));
      expect(valueNames, contains('pending'));
      expect(valueNames, contains('sold'));
    });

    test('parses operationsByTag correctly', () {
      expect(apiDoc.operationsByTag.keys, contains('pets'));
      expect(apiDoc.operationsByTag.keys, contains('users'));
      expect(apiDoc.operationsByTag.keys, contains('orders'));
      expect(apiDoc.operationsByTag['pets']!.length, equals(5));
      expect(apiDoc.operationsByTag['users']!.length, equals(2));
      expect(apiDoc.operationsByTag['orders']!.length, equals(2));
    });

    test('resolves \$ref references for Pet.status', () {
      final pet = apiDoc.schemas['Pet'] as IrObjectSchema;
      final statusProp = pet.properties.firstWhere((p) => p.name == 'status');
      expect(statusProp.schema, isA<IrEnumSchema>());
      expect((statusProp.schema as IrEnumSchema).name, equals('PetStatus'));
    });

    test('resolves \$ref references for Pet.category', () {
      final pet = apiDoc.schemas['Pet'] as IrObjectSchema;
      final catProp = pet.properties.firstWhere((p) => p.name == 'category');
      expect(catProp.schema, isA<IrObjectSchema>());
      expect((catProp.schema as IrObjectSchema).name, equals('Category'));
    });
  });

  group('ModelGeneration', () {
    late IrObjectSchema petSchema;
    late IrEnumSchema petStatusSchema;

    setUp(() {
      petSchema = apiDoc.schemas['Pet'] as IrObjectSchema;
      petStatusSchema = apiDoc.schemas['PetStatus'] as IrEnumSchema;
    });

    test('generates Pet model with fromJson/toJson', () {
      final generated =
          ModelGenerator.generate(petSchema, packageName: 'test_api');
      expect(generated.path, contains('pet.dart'));
      expect(generated.content, contains('class Pet {'));
      expect(generated.content, contains('const Pet({'));
      expect(generated.content, contains('required this.id'));
      expect(generated.content, contains('required this.name'));
      expect(generated.content, contains('this.tag'));
      expect(generated.content, contains('this.status'));
      expect(generated.content,
          contains('factory Pet.fromJson(Map<String, dynamic> json)'));
      expect(generated.content, contains('Map<String, dynamic> toJson()'));
      expect(generated.content, contains('Pet copyWith({'));
      expect(generated.content, contains('bool operator ==(Object other)'));
      expect(generated.content, contains('int get hashCode'));
    });

    test('generates Pet model with correct field types', () {
      final generated =
          ModelGenerator.generate(petSchema, packageName: 'test_api');
      expect(generated.content, contains('final int id;'));
      expect(generated.content, contains('final String name;'));
      expect(generated.content, contains('final String? tag;'));
      expect(generated.content, contains('final PetStatus? status;'));
      expect(generated.content, contains('final Category? category;'));
      expect(generated.content, contains('final List<String>? photoUrls;'));
      expect(generated.content, contains('final DateTime? createdAt;'));
    });

    test('generates Pet model with correct fromJson deserialization', () {
      final generated =
          ModelGenerator.generate(petSchema, packageName: 'test_api');
      expect(generated.content, contains('(json[\'id\'] as num).toInt()'));
      expect(generated.content, contains('json[\'name\'] as String'));
      expect(generated.content,
          contains('PetStatus.fromJson(json[\'status\'] as String'));
      expect(
          generated.content,
          contains(
              'Category.fromJson(json[\'category\'] as Map<String, dynamic>'));
      expect(generated.content,
          contains('DateTime.parse(json[\'createdAt\'] as String'));
      // Primitive lists must be re-wrapped via .cast<T>(): a decoded JSON array is a
      // List<dynamic> at runtime, so a direct `as List<String>` cast throws. Regression
      // guard for the login/roles deserialization crash.
      expect(generated.content,
          contains('(json[\'photoUrls\'] as List).cast<String>()'));
      expect(generated.content, isNot(contains('as List<String>')));
    });

    test('date vs date-time + date/date-time arrays serialize correctly', () {
      // Regression: OpenAPI `format: date` is a calendar date (yyyy-MM-dd) — a full ISO
      // datetime breaks a server binding a date-only type (.NET DateOnly → 400). And a
      // List<DateTime> must be mapped element-by-element (a raw list is not JSON-encodable;
      // a bare .cast<DateTime>() over decoded Strings throws on the way back).
      final spec = <String, dynamic>{
        'openapi': '3.0.0',
        'info': <String, dynamic>{'title': 'T', 'version': '1'},
        'paths': <String, dynamic>{},
        'components': <String, dynamic>{
          'schemas': <String, dynamic>{
            'DatesReq': <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'sourceDate': <String, dynamic>{'type': 'string', 'format': 'date'},
                'targetDates': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string', 'format': 'date'},
                },
                'createdAt': <String, dynamic>{'type': 'string', 'format': 'date-time'},
                'stamps': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{'type': 'string', 'format': 'date-time'},
                },
              },
            },
          },
        },
      };
      final doc = OpenApiSpecParser(spec).parse();
      final generated =
          ModelGenerator.generate(doc.schemas['DatesReq']!, packageName: 'test_api');
      final c = generated.content;

      // date scalar → yyyy-MM-dd (never a full ISO datetime).
      expect(c, contains("sourceDate!.toIso8601String().split('T').first"));
      // date-time scalar → full ISO, NOT truncated.
      expect(c, contains('createdAt!.toIso8601String()'));
      expect(c, isNot(contains("createdAt!.toIso8601String().split")));
      // date array → per-element date-only (a raw List<DateTime> is not JSON-encodable).
      expect(c, contains(".map((e) => e.toIso8601String().split('T').first)"));
      // date-time array → per-element full ISO.
      expect(c, contains('.map((e) => e.toIso8601String())'));
      // NEVER emit a bare List<DateTime> or a .cast<DateTime>() (both crash at runtime).
      expect(c, isNot(contains("'targetDates': targetDates!,")));
      expect(c, isNot(contains('.cast<DateTime>()')));
      // fromJson: date/date-time arrays parse each element.
      expect(c, contains('DateTime.parse(e as String)'));
    });

    test('generates PetStatus enum correctly', () {
      final generated =
          ModelGenerator.generate(petStatusSchema, packageName: 'test_api');
      expect(generated.path, contains('petstatus.dart'));
      expect(generated.content, contains('enum PetStatus {'));
      expect(generated.content, contains("available('available'),"));
      expect(generated.content, contains("pending('pending'),"));
      expect(generated.content, contains("sold('sold');"));
      expect(generated.content,
          contains('static PetStatus fromJson(String json)'));
      expect(generated.content, contains('String toJson()'));
    });

    test('generated code has no double commas', () {
      final generated =
          ModelGenerator.generate(petSchema, packageName: 'test_api');
      expect(generated.content, isNot(contains(',,')));
    });

    test('generated code has no double quotes issues', () {
      final generated =
          ModelGenerator.generate(petSchema, packageName: 'test_api');
      expect(generated.content, isNot(contains('""')));
      expect(generated.content, isNot(contains("''")));
    });

    test('Generated models for all schemas have no syntax errors', () {
      for (final schema in apiDoc.schemas.values) {
        GeneratedFile generated;
        try {
          generated = ModelGenerator.generate(schema, packageName: 'test_api');
        } catch (e) {
          fail('Failed to generate model for ${schema.runtimeType}: $e');
        }
        expect(generated.content, isNotEmpty);
        expect(generated.content, isNot(contains(',,')));
        expect(generated.content, isNot(contains(';;')));
      }
    });
  });

  group('ApiGeneration', () {
    test('generates PetsApi service', () {
      final files = ApiGenerator.generateServices(
        {'pets': apiDoc.operationsByTag['pets']!},
        packageName: 'test_api',
        servers: apiDoc.servers,
      );
      final petsApiFile =
          files.firstWhere((f) => f.path.contains('pets_api.dart'));
      expect(petsApiFile.content, contains('class PetsApi {'));
      expect(petsApiFile.content,
          contains('const PetsApi({required this.dio, this.baseUrl});'));
    });

    test('generates listPets method in PetsApi', () {
      final files = ApiGenerator.generateServices(
        {'pets': apiDoc.operationsByTag['pets']!},
        packageName: 'test_api',
        servers: apiDoc.servers,
      );
      final petsApiFile =
          files.firstWhere((f) => f.path.contains('pets_api.dart'));
      expect(
          petsApiFile.content, contains('Future<ListPetsResult> listPets({'));
    });

    test('generates createPet method in PetsApi with body', () {
      final files = ApiGenerator.generateServices(
        {'pets': apiDoc.operationsByTag['pets']!},
        packageName: 'test_api',
        servers: apiDoc.servers,
      );
      final petsApiFile =
          files.firstWhere((f) => f.path.contains('pets_api.dart'));
      expect(
          petsApiFile.content, contains('Future<CreatePetResult> createPet({'));
      expect(petsApiFile.content, contains('CreatePetRequest'));
    });

    test('generates getPet method with path parameter', () {
      final files = ApiGenerator.generateServices(
        {'pets': apiDoc.operationsByTag['pets']!},
        packageName: 'test_api',
        servers: apiDoc.servers,
      );
      final petsApiFile =
          files.firstWhere((f) => f.path.contains('pets_api.dart'));
      expect(petsApiFile.content, contains('Future<GetPetResult> getPet({'));
      expect(petsApiFile.content, contains('required int petId'));
    });

    test('generates sealed result type for listPets', () {
      final files = ApiGenerator.generateServices(
        {'pets': apiDoc.operationsByTag['pets']!},
        packageName: 'test_api',
        servers: apiDoc.servers,
      );
      final resultFile = files.firstWhere(
        (f) => f.path.contains('listpets_result.dart'),
        orElse: () => fail('listpets_result.dart not found'),
      );
      expect(resultFile.content, contains('sealed class ListPetsResult {'));
      expect(resultFile.content,
          contains('class ListPetsResultHttp200 extends ListPetsResult'));
      expect(
          resultFile.content,
          contains(
              'factory ListPetsResult.fromResponse(Response<dynamic> response)'));
    });

    test('generates root ApiClient with auth', () {
      final clientFile = ApiGenerator.generateRootClient(
        {'pets': apiDoc.operationsByTag['pets']!},
        packageName: 'test_api',
        servers: apiDoc.servers,
        securitySchemes: apiDoc.securitySchemes,
      );
      expect(clientFile.content, contains('class ApiClient {'));
      expect(clientFile.content, contains('BearerAuthSecurity'));
      expect(clientFile.content, contains('PetsApi get pets'));
    });

    test('API generated code has no double commas', () {
      final files = ApiGenerator.generateServices(
        apiDoc.operationsByTag,
        packageName: 'test_api',
        servers: apiDoc.servers,
      );
      for (final f in files) {
        expect(f.content, isNot(contains(',,')),
            reason: 'Double comma in ${f.path}');
        expect(f.content, isNot(contains(';;')),
            reason: 'Double semicolon in ${f.path}');
      }
    });

    test('generates services for all tags', () {
      final files = ApiGenerator.generateServices(
        apiDoc.operationsByTag,
        packageName: 'test_api',
        servers: apiDoc.servers,
      );
      final paths = files.map((f) => f.path).toList();
      expect(paths.any((p) => p.contains('pets_api.dart')), isTrue);
      expect(paths.any((p) => p.contains('users_api.dart')), isTrue);
      expect(paths.any((p) => p.contains('orders_api.dart')), isTrue);
    });
  });

  group('FullPipeline', () {
    test('end-to-end generation produces all expected files', () async {
      final tempDir = Directory.systemTemp.createTempSync('oafg_test_');
      try {
        final generator = CodeGenerator(
          doc: apiDoc,
          outputDir: tempDir.path,
          packageName: 'petstore_client',
          useIsolates: false,
          useCompute: false,
        );
        await generator.generate();

        final outputPath = p.join(tempDir.path, 'petstore_client');
        expect(Directory(outputPath).existsSync(), isTrue);
        expect(File(p.join(outputPath, 'pubspec.yaml')).existsSync(), isTrue);
        expect(File(p.join(outputPath, 'analysis_options.yaml')).existsSync(),
            isTrue);

        final barrelFile =
            File(p.join(outputPath, 'lib', 'petstore_client.dart'));
        expect(barrelFile.existsSync(), isTrue);

        final modelsDir = Directory(p.join(outputPath, 'lib', 'src', 'models'));
        expect(modelsDir.existsSync(), isTrue);
        final modelFiles = modelsDir
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .toList();
        expect(modelFiles, contains('pet.dart'));
        expect(modelFiles, contains('user.dart'));
        expect(modelFiles, contains('order.dart'));
        expect(modelFiles, contains('error.dart'));

        final apiDir = Directory(p.join(outputPath, 'lib', 'src', 'api'));
        expect(apiDir.existsSync(), isTrue);
        final apiFiles = apiDir
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .toList();
        expect(apiFiles, contains('pets_api.dart'));
        expect(apiFiles, contains('users_api.dart'));
        expect(apiFiles, contains('orders_api.dart'));
        expect(apiFiles, contains('api_client.dart'));

        final coreDir = Directory(p.join(outputPath, 'lib', 'src', 'core'));
        expect(coreDir.existsSync(), isTrue);
        expect(File(p.join(coreDir.path, 'auth.dart')).existsSync(), isTrue);
        expect(File(p.join(coreDir.path, 'error_handler.dart')).existsSync(),
            isTrue);
        expect(File(p.join(coreDir.path, 'interceptors.dart')).existsSync(),
            isTrue);
        expect(
            File(p.join(coreDir.path, 'pagination.dart')).existsSync(), isTrue);
      } finally {
        _cleanupDir(tempDir);
      }
    });

    test('generated Pet.dart has no syntax errors', () async {
      final tempDir = Directory.systemTemp.createTempSync('oafg_test2_');
      try {
        final generator = CodeGenerator(
          doc: apiDoc,
          outputDir: tempDir.path,
          packageName: 'test_api',
          useIsolates: false,
          useCompute: false,
        );
        await generator.generate();

        final petFile = File(p.join(
            tempDir.path, 'test_api', 'lib', 'src', 'models', 'pet.dart'));
        final content = petFile.readAsStringSync();
        expect(content, isNot(contains(',,')), reason: 'Found double comma');
        expect(content, isNot(contains(';;')),
            reason: 'Found double semicolon');
        expect(content, isNot(contains('{{')), reason: 'Found double brace');
        expect(content, isNot(contains('}}')), reason: 'Found double brace');
        expect(content, isNot(contains("''")),
            reason: 'Found empty string quotes');
      } finally {
        _cleanupDir(tempDir);
      }
    });

    test('generated code files have no trailing commas in required params',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('oafg_test3_');
      try {
        final generator = CodeGenerator(
          doc: apiDoc,
          outputDir: tempDir.path,
          packageName: 'test_api',
          useIsolates: false,
          useCompute: false,
        );
        await generator.generate();

        final modelsDir =
            Directory(p.join(tempDir.path, 'test_api', 'lib', 'src', 'models'));
        for (final file in modelsDir.listSync().whereType<File>()) {
          final content = file.readAsStringSync();
          expect(content, isNot(contains(',,')),
              reason: 'Double comma in ${p.basename(file.path)}');
        }

        final apiDir =
            Directory(p.join(tempDir.path, 'test_api', 'lib', 'src', 'api'));
        for (final file in apiDir.listSync().whereType<File>()) {
          final content = file.readAsStringSync();
          expect(content, isNot(contains(',,')),
              reason: 'Double comma in ${p.basename(file.path)}');
        }
      } finally {
        _cleanupDir(tempDir);
      }
    });

    test('OAS 3.x petstore with compute compiles', () async {
      final tempDir = Directory.systemTemp.createTempSync('oafg_comp_');
      try {
        final generator = CodeGenerator(
          doc: apiDoc,
          outputDir: tempDir.path,
          packageName: 'petstore_compute',
          useIsolates: false,
          useCompute: true,
        );
        await generator.generate();

        final clientDir = p.join(tempDir.path, 'petstore_compute');
        final pubGet = await Process.run(
          'dart',
          ['pub', 'get'],
          workingDirectory: clientDir,
        );
        expect(pubGet.exitCode, 0,
            reason: 'dart pub get failed:\n${pubGet.stderr}');
        final analyze = await Process.run(
          'dart',
          ['analyze'],
          workingDirectory: clientDir,
        );
        expect(analyze.exitCode, 0,
            reason:
                'dart analyze failed:\n${analyze.stderr}\n${analyze.stdout}');
      } finally {
        _cleanupDir(tempDir);
      }
    });

    group('Swagger 2.0', () {
      test('normalizes Swagger 2.0 Petstore from petstore.swagger.io',
          () async {
        final swaggerPath = p.normalize(
          p.join(p.current, 'test', 'fixtures', 'petstore_swagger.json'),
        );
        final swaggerJson = json.decode(
          await File(swaggerPath).readAsString(),
        ) as Map<String, dynamic>;

        final normalized = SwaggerNormalizer.normalize(swaggerJson);

        expect(normalized['openapi'], '3.0.0');
        expect(normalized['servers'], isNotEmpty);
        expect(normalized['components'], isNotNull);
        expect(
          (normalized['components'] as Map)['schemas'],
          isNotEmpty,
        );

        final parser = OpenApiSpecParser(normalized);
        final doc = parser.parse();

        expect(doc.schemas, isNotEmpty,
            reason: 'Swagger 2.0 schemas should be parsed');
        expect(doc.operations, isNotEmpty,
            reason: 'Swagger 2.0 operations should be parsed');
      });

      test('Swagger 2.0 generated client compiles with dart analyze', () async {
        final swaggerPath = p.normalize(
          p.join(p.current, 'test', 'fixtures', 'petstore_swagger.json'),
        );
        final swaggerJson = json.decode(
          await File(swaggerPath).readAsString(),
        ) as Map<String, dynamic>;

        final normalized = SwaggerNormalizer.normalize(swaggerJson);
        final parser = OpenApiSpecParser(normalized);
        final doc = parser.parse();

        final tempDir = Directory.systemTemp.createTempSync('oafg_swagger_');
        try {
          final generator = CodeGenerator(
            doc: doc,
            outputDir: tempDir.path,
            packageName: 'petstore_client',
            useIsolates: false,
          );
          await generator.generate();

          final clientDir = p.join(tempDir.path, 'petstore_client');

          final pubGet = await Process.run(
            'dart',
            ['pub', 'get'],
            workingDirectory: clientDir,
          );
          expect(pubGet.exitCode, 0,
              reason: 'dart pub get failed:\n${pubGet.stderr}');

          final analyze = await Process.run(
            'dart',
            ['analyze'],
            workingDirectory: clientDir,
          );
          expect(analyze.exitCode, 0,
              reason:
                  'dart analyze failed (exit code ${analyze.exitCode}):\n${analyze.stderr}\n${analyze.stdout}');
        } finally {
          _cleanupDir(tempDir);
        }
      });

      test('does not modify OAS 3.x documents', () {
        final result = SwaggerNormalizer.normalize(petstoreJson);
        expect(result, same(petstoreJson),
            reason: 'OAS 3.x should pass through unchanged');
      });

      test('Swagger 2.0 generated client with compute compiles', () async {
        final swaggerPath = p.normalize(
          p.join(p.current, 'test', 'fixtures', 'petstore_swagger.json'),
        );
        final swaggerJson = json.decode(
          await File(swaggerPath).readAsString(),
        ) as Map<String, dynamic>;

        final normalized = SwaggerNormalizer.normalize(swaggerJson);
        final parser = OpenApiSpecParser(normalized);
        final doc = parser.parse();

        final tempDir = Directory.systemTemp.createTempSync('oafg_swc_');
        try {
          final generator = CodeGenerator(
            doc: doc,
            outputDir: tempDir.path,
            packageName: 'petstore_client',
            useIsolates: false,
            useCompute: true,
          );
          await generator.generate();

          final clientDir = p.join(tempDir.path, 'petstore_client');
          final pubGet = await Process.run(
            'dart',
            ['pub', 'get'],
            workingDirectory: clientDir,
          );
          expect(pubGet.exitCode, 0,
              reason: 'dart pub get failed:\n${pubGet.stderr}');
          final analyze = await Process.run(
            'dart',
            ['analyze'],
            workingDirectory: clientDir,
          );
          expect(analyze.exitCode, 0,
              reason:
                  'dart analyze failed:\n${analyze.stderr}\n${analyze.stdout}');
        } finally {
          _cleanupDir(tempDir);
        }
      });
    });

    group('Train Travel API (OAS 3.1 YAML)', () {
      test('train-travel YAML generated client compiles with dart analyze',
          () async {
        final specPath = p.normalize(
          p.join(p.current, 'test', 'fixtures', 'train_travel.yaml'),
        );
        final specJson = await loadSpec(specPath);

        final parser = OpenApiSpecParser(specJson);
        final doc = parser.parse();

        expect(doc.schemas, isNotEmpty);
        expect(doc.operations, isNotEmpty);

        final tempDir = Directory.systemTemp.createTempSync('oafg_train_');
        try {
          final generator = CodeGenerator(
            doc: doc,
            outputDir: tempDir.path,
            packageName: 'train_travel_client',
            useIsolates: false,
          );
          await generator.generate();

          final clientDir = p.join(tempDir.path, 'train_travel_client');

          final pubGet = await Process.run(
            'dart',
            ['pub', 'get'],
            workingDirectory: clientDir,
          );
          expect(pubGet.exitCode, 0,
              reason: 'dart pub get failed:\n${pubGet.stderr}');

          final analyze = await Process.run(
            'dart',
            ['analyze'],
            workingDirectory: clientDir,
          );
          expect(analyze.exitCode, 0,
              reason:
                  'dart analyze failed (exit code ${analyze.exitCode}):\n${analyze.stderr}\n${analyze.stdout}');
        } finally {
          _cleanupDir(tempDir);
        }
      });

      test('train-travel YAML with compute compiles', () async {
        final specPath = p.normalize(
          p.join(p.current, 'test', 'fixtures', 'train_travel.yaml'),
        );
        final specJson = await loadSpec(specPath);
        final parser = OpenApiSpecParser(specJson);
        final doc = parser.parse();
        expect(doc.schemas, isNotEmpty);
        expect(doc.operations, isNotEmpty);

        final tempDir = Directory.systemTemp.createTempSync('oafg_trainc_');
        try {
          final generator = CodeGenerator(
            doc: doc,
            outputDir: tempDir.path,
            packageName: 'train_travel_client',
            useIsolates: false,
            useCompute: true,
          );
          await generator.generate();

          final clientDir = p.join(tempDir.path, 'train_travel_client');
          final pubGet = await Process.run(
            'dart',
            ['pub', 'get'],
            workingDirectory: clientDir,
          );
          expect(pubGet.exitCode, 0,
              reason: 'dart pub get failed:\n${pubGet.stderr}');
          final analyze = await Process.run(
            'dart',
            ['analyze'],
            workingDirectory: clientDir,
          );
          expect(analyze.exitCode, 0,
              reason:
                  'dart analyze failed:\n${analyze.stderr}\n${analyze.stdout}');
        } finally {
          _cleanupDir(tempDir);
        }
      });
    });
  });

  group('Bearer non-empty guard + multipart enum wire value', () {
    late IrApiDocument bmeDoc;

    setUpAll(() async {
      final fixturePath = p.normalize(
        p.join(p.current, 'test', 'fixtures', 'bearer_multipart_enum.json'),
      );
      final fixtureJson = json.decode(await File(fixturePath).readAsString())
          as Map<String, dynamic>;
      bmeDoc = OpenApiSpecParser(fixtureJson).parse();
    });

    // TEST #1: auth interceptors must stamp the Authorization header ONLY when
    // the token is non-null AND non-empty. A bare `!= null` would send a broken
    // empty `Bearer ` on every anonymous request. Emitted by
    // support_generator.dart into core/auth.dart (interceptor) and, when an
    // AuthInterceptor is emitted, core/interceptors.dart.
    test('emitted auth guards token with isNotEmpty', () async {
      final tempDir = Directory.systemTemp.createTempSync('oafg_bearer_');
      try {
        final generator = CodeGenerator(
          doc: bmeDoc,
          outputDir: tempDir.path,
          packageName: 'bme_client',
          useIsolates: false,
          useCompute: false,
        );
        await generator.generate();

        final coreDir =
            Directory(p.join(tempDir.path, 'bme_client', 'lib', 'src', 'core'));
        final authFile = File(p.join(coreDir.path, 'auth.dart'));
        expect(authFile.existsSync(), isTrue,
            reason: 'core/auth.dart should be emitted');
        final authContent = authFile.readAsStringSync();
        expect(authContent, contains('token.isNotEmpty'),
            reason:
                'auth interceptor must guard the token with isNotEmpty, not a bare != null');

        // If an AuthInterceptor is emitted in core/interceptors.dart, it must
        // apply the same non-empty guard.
        final interceptorsFile = File(p.join(coreDir.path, 'interceptors.dart'));
        if (interceptorsFile.existsSync()) {
          final interceptorsContent = interceptorsFile.readAsStringSync();
          if (interceptorsContent.contains('AuthInterceptor')) {
            expect(interceptorsContent, contains('.isNotEmpty'),
                reason:
                    'AuthInterceptor must guard the token with isNotEmpty');
          }
        }
      } finally {
        _cleanupDir(tempDir);
      }
    });

    // TEST #2: enum fields in a multipart toFormData() must serialize to their
    // WIRE value via `.toJson().toString()` (NOT a bare `.toString()`, which
    // emits `EnumType.name` a server cannot bind). Additionally, a binary
    // multipart part must be `MultipartFile.fromBytes(bytes, filename: '<key>')`
    // with NO caller-settable FileName/ContentType sibling fields (locks the
    // reverted experiment). Emitted by model_generator.dart _generateToFormData.
    test('multipart enum serializes via toJson wire value, binary has no '
        'FileName/ContentType siblings', () {
      final uploadSchema = bmeDoc.schemas['UploadRequest'] as IrObjectSchema;
      final generated =
          ModelGenerator.generate(uploadSchema, packageName: 'bme_client');
      final content = generated.content;

      // toFormData must be emitted (binary property triggers it).
      expect(content, contains('FormData toFormData()'),
          reason: 'binary property should trigger toFormData emission');

      // Enum field serialized via toJson().toString() wire value.
      expect(content, contains('kind.toJson().toString()'),
          reason:
              'enum multipart field must serialize its wire value via toJson()');
      // And NOT via a bare enum .toString() (which would emit EnumType.name).
      expect(content, isNot(contains('kind.toString()')),
          reason: 'enum field must not be serialized with a bare toString()');

      // Binary part is fromBytes with filename set to the json key, and has no
      // caller-settable filename/content-type sibling fields.
      expect(content, contains("MultipartFile.fromBytes("),
          reason: 'binary part must use MultipartFile.fromBytes');
      expect(content, contains("filename: 'file'"),
          reason: 'binary part filename must be the json key');
      expect(content, isNot(contains('FileName')),
          reason: 'no caller-settable FileName sibling field on binary part');
      expect(content, isNot(contains('ContentType')),
          reason: 'no caller-settable ContentType sibling field on binary part');
    });
  });
}
