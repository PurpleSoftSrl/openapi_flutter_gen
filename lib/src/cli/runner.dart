import '../parser/loader.dart';
import '../parser/openapi_parser.dart';
import '../parser/swagger_normalizer.dart';
import '../generator/generator.dart';
import '../generator/runtime_generator.dart';

class Runner {
  Future<void> run({
    required String specPath,
    String? specUrl,
    required String outputDir,
    String packageName = 'api_client',
    bool useIsolates = true,
    bool useCompute = false,
    bool pureSurface = false,
    String corePackage = 'purple_openapi_core',
    String emitTarget = 'client',
  }) async {
    if (emitTarget == 'runtime') {
      print('Emitting runtime package: $corePackage');
      await RuntimePackageGenerator(
              outputDir: outputDir, packageName: corePackage)
          .generate();
      print('Done!');
      return;
    }

    print('Loading spec...');
    final specJson = specUrl != null
        ? await loadSpecFromUrl(specUrl)
        : await loadSpec(specPath);

    final normalized = SwaggerNormalizer.normalize(specJson);

    print('Parsing OpenAPI spec...');
    final parser = OpenApiSpecParser(normalized);
    final apiDoc = parser.parse();

    print(
        'Parsed: ${apiDoc.schemas.length} schemas, ${apiDoc.operations.length} operations');
    print('Tags: ${apiDoc.operationsByTag.keys.join(', ')}');

    print('Generating Dart code...');
    final generator = CodeGenerator(
      doc: apiDoc,
      outputDir: outputDir,
      packageName: packageName,
      useIsolates: useIsolates,
      useCompute: useCompute,
      pureSurface: pureSurface,
      corePackage: corePackage,
    );

    await generator.generate();

    print('Done!');
    print('');
    print('Generated package: $packageName');
    print('Output directory: $outputDir');
    print('');
    print('Next steps:');
    print('  cd $outputDir/$packageName');
    print('  dart pub get');
    print('  # Then import and use in your Flutter/Dart app:');
    print("  # import 'package:$packageName/$packageName.dart';");
  }
}
