import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:openapi_flutter_gen/src/parser/swagger_normalizer.dart';
import 'package:openapi_flutter_gen/src/parser/openapi_parser.dart';
import 'package:openapi_flutter_gen/src/generator/generator.dart';

void main() async {
  final swagger = json.decode(
    File('../test_specs/petstore_swagger.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  
  final normalized = SwaggerNormalizer.normalize(swagger);
  final parser = OpenApiSpecParser(normalized);
  final doc = parser.parse();
  
  final tempDir = Directory.systemTemp.createTempSync('debug_swagger_');
  final generator = CodeGenerator(
    doc: doc, outputDir: tempDir.path, packageName: 'petstore',
    useIsolates: false,
  );
  await generator.generate();
  
  final dir = p.join(tempDir.path, 'petstore');
  
  // Check createuser_result
  print('=== createuser_result.dart ===');
  print(File(p.join(dir, 'lib/src/api/createuser_result.dart')).readAsStringSync());
  
  print('\n=== get200response.dart ===');
  print(File(p.join(dir, 'lib/src/models/get200response.dart')).readAsStringSync());
  
  print('\n=== Pet model ===');
  print(File(p.join(dir, 'lib/src/models/pet.dart')).readAsStringSync());
  
  tempDir.deleteSync(recursive: true);
}
