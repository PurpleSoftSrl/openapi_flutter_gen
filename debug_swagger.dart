import 'dart:convert';
import 'dart:io';
import 'package:openapi_flutter_gen/src/parser/swagger_normalizer.dart';

void main() {
  final swagger = json.decode(
    File('../test_specs/petstore_swagger.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  
  final normalized = SwaggerNormalizer.normalize(swagger);
  final schemas = (normalized['components'] as Map)['schemas'] as Map;
  
  print('Schemas: ${schemas.keys.join(' ')}');
  print('Has PetStatus: ${schemas.containsKey('PetStatus')}');
  print('Has OrderStatus: ${schemas.containsKey('OrderStatus')}');
  
  final pet = schemas['Pet'] as Map?;
  if (pet != null) {
    final props = pet['properties'] as Map;
    final statusProp = props['status'];
    print('\nPet.status: ${json.encode(statusProp)}');
  }
}
