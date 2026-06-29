import 'package:openapi_flutter_gen/openapi_flutter_gen.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print(
        'Usage: dart run example/main.dart <spec-file> [output-dir] [--use-compute]');
    return;
  }

  final specPath = args[0];
  final outputDir = args.length > 1 ? args[1] : 'generated_client';
  final useCompute = args.contains('--use-compute');

  // Parse the spec
  final Map<String, dynamic> doc;
  if (specPath.startsWith('http://') || specPath.startsWith('https://')) {
    doc = await loadSpecFromUrl(specPath);
  } else {
    doc = await loadSpec(specPath);
  }

  // Normalize Swagger 2.0 if needed
  final normalized = SwaggerNormalizer.normalize(doc);

  // Parse and generate
  final parser = OpenApiSpecParser(normalized);
  final irDoc = parser.parse();

  final generator = CodeGenerator(
    doc: irDoc,
    outputDir: outputDir,
    packageName: 'api_client',
    useCompute: useCompute,
  );

  await generator.generate();
  print('Generation completed successfully.');
}
