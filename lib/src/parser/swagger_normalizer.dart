/// Normalizes Swagger 2.0 / OpenAPI 2.x documents into OpenAPI 3.x-compatible
/// JSON so the main [OpenApiSpecParser] can process them without any awareness
/// of the legacy format.
///
/// This is a pre-processing step. The parser stays single-responsibility (OAS 3.x)
/// and this converter handles all legacy mapping in one place.
class SwaggerNormalizer {
  SwaggerNormalizer._();

  static Map<String, dynamic> normalize(Map<String, dynamic> swagger) {
    if (!_isSwagger2(swagger)) return swagger;

    final result = <String, dynamic>{};
    result['openapi'] = '3.0.0';

    _normalizeInfo(swagger, result);
    _normalizeServers(swagger, result);
    _normalizePaths(swagger, result);
    _normalizeSchemas(swagger, result);
    _normalizeSecurity(swagger, result);

    return result;
  }

  static bool _isSwagger2(Map<String, dynamic> doc) =>
      doc.containsKey('swagger') && doc['swagger'] is String;

  static void _normalizeInfo(
      Map<String, dynamic> src, Map<String, dynamic> dst) {
    final info = src['info'];
    if (info is Map<String, dynamic>) {
      dst['info'] = Map<String, dynamic>.from(info);
    }
  }

  static void _normalizeServers(
      Map<String, dynamic> src, Map<String, dynamic> dst) {
    final host = src['host'] as String? ?? 'localhost';
    final basePath = src['basePath'] as String? ?? '/';
    final schemes =
        (src['schemes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            ['https'];

    final servers = <Map<String, dynamic>>[];
    for (final scheme in schemes) {
      servers.add({'url': '$scheme://$host$basePath'});
    }
    dst['servers'] = servers;
  }

  static void _normalizeSchemas(
      Map<String, dynamic> src, Map<String, dynamic> dst) {
    final definitions = src['definitions'];
    if (definitions is Map<String, dynamic>) {
      dst['components'] = {'schemas': _convertDefinitions(definitions)};
    }
  }

  static Map<String, dynamic> _convertDefinitions(
      Map<String, dynamic> definitions) {
    final result = <String, dynamic>{};
    for (final entry in definitions.entries) {
      if (entry.value is Map<String, dynamic>) {
        final schema = entry.value as Map<String, dynamic>;
        _extractInlineSchemas(result, entry.key, schema);
        result[entry.key] = _convertPropertySchema(schema);
      }
    }
    return result;
  }

  /// Extracts inline enum and object property schemas as separate named schemas.
  static void _extractInlineSchemas(Map<String, dynamic> target,
      String parentName, Map<String, dynamic> schema) {
    final rawProps = schema['properties'];
    if (rawProps is! Map<String, dynamic>) return;
    final props = rawProps;
    for (final entry in props.entries) {
      if (entry.value is Map<String, dynamic>) {
        final prop = entry.value as Map<String, dynamic>;
        final propName = _toPascalCase(entry.key);
        final inlineName = '${parentName}$propName';
        final shouldExtract = prop.containsKey('enum') ||
            ((prop['type'] == 'object' || prop.containsKey('properties')) &&
                !prop.containsKey(r'$ref'));
        if (shouldExtract && !target.containsKey(inlineName)) {
          target[inlineName] = _convertPropertySchema(prop);
          props[entry.key] = {'\$ref': '#/components/schemas/$inlineName'};
        }
      }
    }
  }

  static String _toPascalCase(String s) {
    if (s.isEmpty) return s;
    return s
        .split(RegExp(r'[\._\-\s]+'))
        .map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1))
        .join();
  }

  static Map<String, dynamic> _convertPropertySchema(
      Map<String, dynamic> schema) {
    final result = <String, dynamic>{};

    result['type'] = schema['type'] ?? 'object';

    if (schema.containsKey(r'$ref')) {
      result[r'$ref'] = (schema[r'$ref'] as String)
          .replaceFirst('#/definitions/', '#/components/schemas/');
      return result;
    }

    if (schema.containsKey('properties')) {
      final props = schema['properties'];
      if (props is Map<String, dynamic>) {
        final converted = <String, dynamic>{};
        for (final entry in props.entries) {
          if (entry.value is Map<String, dynamic>) {
            converted[entry.key] =
                _convertPropertySchema(entry.value as Map<String, dynamic>);
          }
        }
        result['properties'] = converted;
      }
    }

    if (schema.containsKey('items')) {
      final items = schema['items'];
      if (items is Map<String, dynamic>) {
        result['items'] = _convertPropertySchema(items);
      }
    }

    if (schema.containsKey('required')) result['required'] = schema['required'];

    for (final key in [
      'description',
      'format',
      'enum',
      'default',
      'nullable',
      'minimum',
      'maximum',
      'minLength',
      'maxLength',
      'pattern',
      'additionalProperties',
      'discriminator'
    ]) {
      if (schema.containsKey(key)) result[key] = schema[key];
    }

    return result;
  }

  static void _normalizePaths(
      Map<String, dynamic> src, Map<String, dynamic> dst) {
    final paths = src['paths'];
    if (paths is! Map<String, dynamic>) return;

    final result = <String, dynamic>{};
    for (final entry in paths.entries) {
      if (entry.value is! Map<String, dynamic>) continue;
      result[entry.key] = _convertPathItem(entry.value as Map<String, dynamic>);
    }
    dst['paths'] = result;
  }

  static Map<String, dynamic> _convertPathItem(Map<String, dynamic> pathItem) {
    final result = <String, dynamic>{};

    final pathParams = (pathItem['parameters'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];

    for (final method in [
      'get',
      'post',
      'put',
      'delete',
      'patch',
      'options',
      'head'
    ]) {
      final operation = pathItem[method];
      if (operation is! Map<String, dynamic>) continue;
      result[method] = _convertOperation(operation, pathParams);
    }

    return result;
  }

  static Map<String, dynamic> _convertOperation(
      Map<String, dynamic> operation, List<Map<String, dynamic>> pathParams) {
    final result = Map<String, dynamic>.from(operation);

    final allParams = <Map<String, dynamic>>[...pathParams];
    final opParams = (operation['parameters'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];

    final convertedParams = <Map<String, dynamic>>[];
    Map<String, dynamic>? requestBody;

    for (final param in [...allParams, ...opParams]) {
      if (param['in'] == 'body') {
        final schema = param['schema'];
        requestBody = {
          'description': param['description'] ?? '',
          'required': param['required'] ?? false,
          'content': {
            'application/json': {
              'schema': schema is Map<String, dynamic>
                  ? _convertPropertySchema(schema)
                  : schema,
            },
          },
        };
      } else {
        convertedParams.add({
          'name': param['name'],
          'in': param['in'] ?? 'query',
          'required': param['required'] ?? false,
          'description': param['description'],
          'schema': param,
          'type': param['type'],
        });
      }
    }

    result['parameters'] = convertedParams;
    if (requestBody != null) result['requestBody'] = requestBody;

    final consumes = operation['consumes'] as List<dynamic>?;
    if (consumes != null && requestBody != null && consumes.isNotEmpty) {
      final content = <String, dynamic>{};
      for (final ct in consumes) {
        content[ct.toString()] = requestBody['content']['application/json'];
      }
      requestBody['content'] = content;
    }

    _convertOperationResponses(result, operation);

    return result;
  }

  static void _convertOperationResponses(
      Map<String, dynamic> result, Map<String, dynamic> operation) {
    final responses = operation['responses'];
    if (responses is! Map<String, dynamic>) return;

    final converted = <String, dynamic>{};
    for (final entry in responses.entries) {
      if (entry.value is Map<String, dynamic>) {
        final resp =
            Map<String, dynamic>.from(entry.value as Map<String, dynamic>);
        final schema = resp['schema'];
        if (schema is Map<String, dynamic>) {
          resp['content'] = {
            'application/json': {
              'schema': _convertPropertySchema(schema),
            },
          };
        }
        resp.remove('schema');
        converted[entry.key] = resp;
      }
    }
    result['responses'] = converted;
  }

  static void _normalizeSecurity(
      Map<String, dynamic> src, Map<String, dynamic> dst) {
    final defs = src['securityDefinitions'];
    if (defs is Map<String, dynamic>) {
      final result = <String, dynamic>{};
      for (final entry in defs.entries) {
        if (entry.value is Map<String, dynamic>) {
          final s =
              Map<String, dynamic>.from(entry.value as Map<String, dynamic>);
          result[entry.key] = s;
        }
      }
      dst['components'] ??= <String, dynamic>{};
      (dst['components'] as Map<String, dynamic>)['securitySchemes'] = result;
    }
  }
}
