import '../../ir/ir.dart';
import '../../util/type_utils.dart';
import 'naming.dart';
import 'model_generator.dart';

class ApiGenerator {
  static List<GeneratedFile> generateServices(
    Map<String, List<IrOperation>> operationsByTag, {
    required String packageName,
    required List<IrServer> servers,
    bool useCompute = false,
  }) {
    final files = <GeneratedFile>[];

    for (final entry in operationsByTag.entries) {
      final tag = entry.key;
      final ops = entry.value;
      files.add(_generateService(tag, ops,
          packageName: packageName, servers: servers, useCompute: useCompute));

      for (final op in ops) {
        final responseGen = _generateOperationResponse(op,
            packageName: packageName, useCompute: useCompute);
        if (responseGen != null) files.add(responseGen);
      }
    }

    return files;
  }

  static GeneratedFile _generateService(
    String tag,
    List<IrOperation> ops, {
    required String packageName,
    required List<IrServer> servers,
    bool useCompute = false,
  }) {
    final buf = StringBuffer(generateFileHeader());
    final className = '${sanitizeClassName(tag)}Api';

    buf.writeln('import \'package:dio/dio.dart\';');
    if (useCompute) {
      buf.writeln('import \'dart:isolate\';');
    }

    final needsTypedData = ops.any((op) =>
        op.requestBody != null &&
        op.requestBody!.content.values.any((mt) =>
            mt.schema is IrPrimitiveSchema &&
            (mt.schema as IrPrimitiveSchema).type == IrPrimitiveType.binary));

    if (needsTypedData) {
      buf.writeln('import \'dart:typed_data\';');
    }
    buf.writeln();

    final modelImports = <String>{};
    for (final op in ops) {
      for (final param in op.parameters) {
        final importName = _schemaImportName(param.schema);
        if (importName != null) modelImports.add(importName);
      }
      if (op.requestBody != null) {
        for (final mt in op.requestBody!.content.values) {
          final importName = _schemaImportName(mt.schema);
          if (importName != null) modelImports.add(importName);
        }
      }
    }

    for (final imp in modelImports.toList()..sort()) {
      buf.writeln('import \'../models/${imp.toLowerCase()}.dart\';');
    }

    final resultImports = <String>{};
    for (final op in ops) {
      final cleanName =
          sanitizeFieldName(op.operationId).replaceAll(RegExp(r'_+$'), '');
      final resultFileName = '${cleanName}_result';
      resultImports.add(resultFileName);
    }
    for (final imp in resultImports.toList()..sort()) {
      buf.writeln('import \'${imp.toLowerCase()}.dart\';');
    }
    buf.writeln();

    buf.writeln('class $className {');
    buf.writeln('  const $className({required this.dio, this.baseUrl});');
    buf.writeln();
    buf.writeln('  final Dio dio;');
    buf.writeln('  final String? baseUrl;');
    buf.writeln();

    for (final op in ops) {
      _generateOperationMethod(buf, op, className, useCompute: useCompute);
    }

    buf.writeln('}');

    return GeneratedFile(
      path: 'lib/src/api/${sanitizeClassName(tag).toLowerCase()}_api.dart',
      content: buf.toString(),
    );
  }

  static void _generateOperationMethod(
      StringBuffer buf, IrOperation op, String className,
      {bool useCompute = false}) {
    final methodName = sanitizeFieldName(op.operationId);
    final httpMethod = op.httpMethod.toLowerCase();
    final resultType = '${sanitizeClassName(op.operationId)}Result';

    if (op.description != null) {
      buf.writeln('  /// ${op.description!.replaceAll('\n', '\n  /// ')}');
    }

    buf.write('  Future<$resultType> $methodName({');

    final methodParams = _methodParams(op);

    for (int i = 0; i < methodParams.length; i++) {
      final mp = methodParams[i];
      buf.writeln();
      buf.write('    $mp,');
    }

    final hasPreviousParams = methodParams.isNotEmpty;
    if (hasPreviousParams) buf.writeln();

    buf.write('    ');
    buf.writeln('CancelToken? cancelToken,');
    buf.writeln('    Map<String, dynamic>? extra,');
    buf.writeln('    Options? options,');
    buf.writeln('  }) async {');

    final hasHeaderParams =
        op.parameters.any((p) => p.location == IrParameterLocation.header);
    final hasQueryParams =
        op.parameters.any((p) => p.location == IrParameterLocation.query);

    if (hasHeaderParams) {
      buf.writeln('    final reqHeaders = <String, dynamic>{};');
    }
    if (hasQueryParams) {
      buf.writeln('    final reqQueryParams = <String, dynamic>{};');
    }

    for (final param in op.parameters) {
      final pName = sanitizeFieldName(param.name);
      switch (param.location) {
        case IrParameterLocation.header:
          buf.writeln(
              '    if ($pName != null) { reqHeaders[\'${param.name}\'] = ${_serializeParamExpr(pName, param.schema)}; }');
          break;
        case IrParameterLocation.query:
          buf.writeln(
              '    if ($pName != null) { reqQueryParams[\'${param.name}\'] = ${_serializeParamExpr(pName, param.schema)}; }');
          break;
        default:
          break;
      }
    }

    buf.writeln();

    final pathUrl = _buildPathUrl(op);

    buf.writeln(
        '    final response = await dio.request<Map<String, dynamic>>(');
    buf.writeln('      \'$pathUrl\',');

    final hasBody = op.requestBody != null &&
        op.requestBody!.content.isNotEmpty &&
        op.requestBody!.content.values.first.schema != null;
    final isMultipart = hasBody &&
        op.requestBody!.content.keys.any((ct) => ct.contains('multipart'));
    final isBinary = hasBody &&
        op.requestBody!.content.values.any((mt) {
          final s = mt.schema;
          return s is IrPrimitiveSchema && s.type == IrPrimitiveType.binary;
        }) &&
        !isMultipart;

    if (hasBody) {
      final paramName = _bodyParamName(op) ?? 'body';
      final isRequired = op.requestBody!.isRequired;
      final bodySchema = op.requestBody!.content.values.first.schema;
      final needsToJson = _needsToJson(bodySchema);

      if (isMultipart) {
        final suffix = isRequired ? '.toFormData()' : '?.toFormData()';
        buf.writeln('      data: $paramName$suffix,');
      } else if (isBinary && bodySchema is IrPrimitiveSchema) {
        buf.writeln('      data: Stream.fromIterable([$paramName]),');
      } else {
        String suffix;
        if (needsToJson && bodySchema is IrListSchema) {
          suffix = isRequired
              ? '.map((e) => e.toJson()).toList()'
              : '?.map((e) => e.toJson()).toList()';
        } else if (needsToJson) {
          suffix = isRequired ? '.toJson()' : '?.toJson()';
        } else {
          suffix = '';
        }
        buf.writeln('      data: $paramName$suffix,');
      }
    }

    final hasBinaryResponse =
        op.responses.any((r) => r.content.values.any((mt) {
              final s = mt.schema;
              return s is IrPrimitiveSchema && s.type == IrPrimitiveType.binary;
            }));

    if (hasQueryParams) {
      buf.write(
          '      queryParameters: reqQueryParams.isNotEmpty ? reqQueryParams : null,');
    } else {
      buf.write('      queryParameters: null,');
    }
    buf.writeln();
    buf.writeln('      options: options ?? Options(');
    buf.writeln('        method: \'$httpMethod\',');
    if (hasHeaderParams) {
      buf.writeln(
          '        headers: reqHeaders.isNotEmpty ? reqHeaders : null,');
    } else {
      buf.writeln('        headers: null,');
    }
    buf.writeln('        extra: extra,');
    if (hasBinaryResponse) {
      buf.writeln('        responseType: ResponseType.bytes,');
    }
    buf.writeln('      ),');
    buf.writeln('      cancelToken: cancelToken,');
    buf.writeln('    );');
    buf.writeln();

    if (useCompute) {
      final funcName = 'deserialize${sanitizeClassName(op.operationId)}';
      buf.writeln('    final statusCode = response.statusCode ?? 0;');
      buf.writeln('    final data = response.data;');
      buf.writeln(
          '    return Isolate.run(() => $funcName((statusCode: statusCode, data: data)));');
    } else {
      buf.writeln('    return $resultType.fromResponse(response);');
    }
    buf.writeln('  }');
    buf.writeln();
  }

  static List<String> _methodParams(IrOperation op) {
    final params = <String>[];

    for (final param in op.parameters) {
      final typeStr = schemaToDartType(param.schema);
      final pName = sanitizeFieldName(param.name);

      if (param.location == IrParameterLocation.path) {
        params.add('required $typeStr $pName');
      } else {
        final alreadyNullable = typeStr.endsWith('?');
        params.add(alreadyNullable ? '$typeStr $pName' : '$typeStr? $pName');
      }
    }

    if (op.requestBody != null &&
        op.requestBody!.content.isNotEmpty &&
        op.requestBody!.content.values.first.schema != null) {
      final mt = op.requestBody!.content.values.first;
      final schema = mt.schema;
      if (schema != null) {
        final typeStr = schemaToDartType(schema);
        final pName = _bodyParamName(op) ?? 'body';
        final isRequired = op.requestBody!.isRequired;
        if (isRequired) {
          params.add('required $typeStr $pName');
        } else {
          final alreadyNullable = typeStr.endsWith('?');
          params.add(alreadyNullable ? '$typeStr $pName' : '$typeStr? $pName');
        }
      }
    }

    return params;
  }

  static String? _bodyParamName(IrOperation op) {
    if (op.requestBody == null || op.requestBody!.content.isEmpty) return null;
    final schema = op.requestBody!.content.values.first.schema;
    if (schema is IrRefSchema) return sanitizeFieldName(schema.refName);
    if (schema is IrObjectSchema) return sanitizeFieldName(schema.name);
    return 'body';
  }

  static String _serializeParamExpr(String expr, IrSchema schema) {
    switch (schema) {
      case IrObjectSchema():
        return '$expr.toJson().toString()';
      case IrEnumSchema():
        return '$expr.toJson().toString()';
      case IrPrimitiveSchema(type: IrPrimitiveType.dateTime):
        return '$expr.toIso8601String()';
      case IrPrimitiveSchema():
        return '$expr.toString()';
      default:
        return '$expr.toString()';
    }
  }

  static String _buildPathUrl(IrOperation op) {
    var path = op.path;
    for (final param in op.parameters) {
      if (param.location == IrParameterLocation.path) {
        final pName = sanitizeFieldName(param.name);
        path = path.replaceAll('{${param.name}}', '\$$pName');
      }
    }
    return path;
  }

  static GeneratedFile? _generateOperationResponse(IrOperation op,
      {required String packageName, bool useCompute = false}) {
    final buf = StringBuffer(generateFileHeader());
    buf.writeln('// ignore_for_file: unused_import, unnecessary_cast');
    buf.writeln();
    final className = '${sanitizeClassName(op.operationId)}Result';

    buf.writeln('import \'package:dio/dio.dart\';');

    var needsTypedData = false;
    for (final resp in op.responses) {
      for (final mt in resp.content.values) {
        if (mt.schema is IrPrimitiveSchema &&
            (mt.schema as IrPrimitiveSchema).type == IrPrimitiveType.binary) {
          needsTypedData = true;
        }
      }
    }
    if (needsTypedData) {
      buf.writeln('import \'dart:typed_data\';');
    }
    buf.writeln();

    final imports = <String>{};
    for (final resp in op.responses) {
      for (final mt in resp.content.values) {
        final importName = _schemaImportName(mt.schema);
        if (importName != null) imports.add(importName);
      }
    }

    for (final imp in imports.toList()..sort()) {
      buf.writeln('import \'../models/${imp.toLowerCase()}.dart\';');
    }
    buf.writeln();

    buf.writeln('sealed class $className {');
    buf.writeln('  const $className();');
    buf.writeln();

    _generateResultFromResponse(buf, op);
    buf.writeln();

    buf.writeln('}');
    buf.writeln();

    for (final resp in op.responses) {
      _generateResultVariant(buf, resp, className);
      buf.writeln();
    }

    _generateErrorVariant(buf, className);

    if (useCompute) {
      _generateComputeDeserializer(buf, op, className);
    }

    return GeneratedFile(
      path:
          'lib/src/api/${sanitizeClassName(op.operationId).toLowerCase()}_result.dart',
      content: buf.toString(),
    );
  }

  static void _generateResultFromResponse(StringBuffer buf, IrOperation op) {
    final className = '${sanitizeClassName(op.operationId)}Result';

    buf.writeln(
        '  factory $className.fromResponse(Response<dynamic> response) {');
    buf.writeln('    final statusCode = response.statusCode ?? 0;');
    buf.writeln('    return switch (statusCode) {');

    for (final resp in op.responses) {
      final status = resp.statusCode;
      if (status == 'default') continue;

      final variantName = '${className}Http$status';
      final mt = resp.content.values.firstOrNull;
      final schema = mt?.schema;

      if (schema != null) {
        buf.write('      $status => $variantName(');
        buf.write(_fromJsonExpr('response.data', schema));
        buf.writeln('),');
      } else {
        buf.writeln('      $status => const $variantName(),');
      }
    }

    final defaultResp = op.responses.cast<IrResponse?>().firstWhere(
          (r) => r?.statusCode == 'default',
          orElse: () => null,
        );

    if (defaultResp != null) {
      final defaultSchema = defaultResp.content.values.firstOrNull?.schema;
      if (defaultSchema != null) {
        buf.writeln(
            '      _ => ${className}HttpDefault(${_fromJsonExpr('response.data', defaultSchema)}),');
      } else {
        buf.writeln('      _ => const ${className}HttpDefault(),');
      }
    } else {
      buf.writeln('      _ => ${className}Error.fromResponse(response),');
    }

    buf.writeln('    };');
    buf.writeln('  }');
  }

  static void _generateResultVariant(
      StringBuffer buf, IrResponse resp, String parentName) {
    final statusName =
        resp.statusCode == 'default' ? 'Default' : resp.statusCode;
    final variantName = '${parentName}Http$statusName';
    final mt = resp.content.values.firstOrNull;
    final schema = mt?.schema;

    if (schema != null) {
      final typeStr = schemaToDartType(schema);
      buf.writeln('class $variantName extends $parentName {');
      buf.writeln('  const $variantName(this.data);');
      buf.writeln('  final $typeStr data;');
      buf.writeln('}');
    } else {
      buf.writeln('class $variantName extends $parentName {');
      buf.writeln('  const $variantName();');
      buf.writeln('}');
    }
  }

  static void _generateErrorVariant(StringBuffer buf, String parentName) {
    final hasDefault = false;

    if (!hasDefault) {
      buf.writeln('class ${parentName}Error extends $parentName {');
      buf.writeln('  const ${parentName}Error(this.response);');
      buf.writeln('  final Response<dynamic> response;');
      buf.writeln();
      buf.writeln(
          '  factory ${parentName}Error.fromResponse(Response<dynamic> response) => ${parentName}Error(response);');
      buf.writeln('}');
    }
  }

  static String _fromJsonExpr(String expr, IrSchema? schema) {
    if (schema == null) return expr;
    switch (schema) {
      case IrObjectSchema():
        return '${sanitizeClassName(schema.name)}.fromJson($expr as Map<String, dynamic>)';
      case IrEnumSchema():
        return '${sanitizeClassName(schema.name)}.fromJson($expr as ${schema.enumType == IrPrimitiveType.integer ? "int" : "String"})';
      case IrUnionSchema():
        return '${sanitizeClassName(schema.name)}.fromJson($expr as Map<String, dynamic>)';
      case IrRefSchema():
        return '${sanitizeClassName(schema.refName)}.fromJson($expr as Map<String, dynamic>)';
      case IrListSchema():
        if (schema.items is IrObjectSchema) {
          return 'List<${sanitizeClassName((schema.items as IrObjectSchema).name)}>.generate(($expr as List).length, (i) => ${sanitizeClassName((schema.items as IrObjectSchema).name)}.fromJson(($expr as List)[i] as Map<String, dynamic>), growable: false)';
        }
        if (schema.items is IrRefSchema) {
          return 'List<${sanitizeClassName((schema.items as IrRefSchema).refName)}>.generate(($expr as List).length, (i) => ${sanitizeClassName((schema.items as IrRefSchema).refName)}.fromJson(($expr as List)[i] as Map<String, dynamic>), growable: false)';
        }
        return expr;
      case IrPrimitiveSchema(type: IrPrimitiveType.integer):
        return '($expr as num).toInt()';
      case IrPrimitiveSchema(type: IrPrimitiveType.number):
        return '($expr as num).toDouble()';
      case IrPrimitiveSchema():
        return '$expr as ${dartTypeFromPrimitive(schema.type)}';
      case IrMapSchema():
        return '$expr as Map<String, dynamic>';
    }
  }

  static String? _schemaImportName(IrSchema? schema) {
    return switch (schema) {
      IrRefSchema() => sanitizeClassName(schema.refName),
      IrObjectSchema() => sanitizeClassName(schema.name),
      IrEnumSchema() => sanitizeClassName(schema.name),
      IrUnionSchema() => sanitizeClassName(schema.name),
      IrListSchema() => _schemaImportName(schema.items),
      _ => null,
    };
  }

  static GeneratedFile generateRootClient(
    Map<String, List<IrOperation>> operationsByTag, {
    required String packageName,
    required List<IrServer> servers,
    required Map<String, IrSecurityScheme> securitySchemes,
    bool useCompute = false,
  }) {
    final buf = StringBuffer(generateFileHeader());
    buf.writeln('import \'package:dio/dio.dart\';');
    for (final _ in securitySchemes.keys) {
      buf.writeln('import \'../core/auth.dart\';');
      break;
    }
    buf.writeln('import \'../core/error_handler.dart\';');
    buf.writeln();

    for (final tag in operationsByTag.keys) {
      buf.writeln(
          'import \'${sanitizeClassName(tag).toLowerCase()}_api.dart\';');
    }
    buf.writeln();

    buf.writeln('class ApiClient {');
    buf.writeln('  ApiClient({');
    if (servers.isNotEmpty) {
      final server = servers.first;
      buf.writeln('    this.baseUrl = \'${server.url}\',');
    } else {
      buf.writeln('    this.baseUrl = \'\',');
    }

    for (final entry in securitySchemes.entries) {
      final name = entry.key;
      final camelName = sanitizeFieldName(name);
      buf.writeln('    this.$camelName,');
    }

    buf.writeln('    this.errorHandler,');
    buf.writeln('    Dio? dio,');
    buf.writeln('    this.interceptors,');
    buf.write('  }) : _dio = dio ?? Dio()');
    if (securitySchemes.isNotEmpty) {
      buf.writeln(' {');
      buf.writeln('    _dio.options.baseUrl = baseUrl;');
      buf.writeln(
          '    if (errorHandler != null) { _addInterceptor(errorHandler!); }');
      for (final entry in securitySchemes.entries) {
        final camelName = sanitizeFieldName(entry.key);
        buf.writeln('    final ${camelName}Copy = $camelName;');
        buf.writeln(
            '    if (${camelName}Copy != null) { _addInterceptor(${camelName}Copy.createInterceptor()); }');
      }
      buf.writeln(
          '    if (interceptors != null) { _addInterceptors(interceptors!); }');
      buf.writeln('  }');
    } else {
      buf.writeln(' {');
      buf.writeln('    _dio.options.baseUrl = baseUrl;');
      buf.writeln(
          '    if (errorHandler != null) { _addInterceptor(errorHandler!); }');
      buf.writeln(
          '    if (interceptors != null) { _addInterceptors(interceptors!); }');
      buf.writeln('  }');
    }
    buf.writeln();

    buf.writeln('  final String baseUrl;');

    for (final entry in securitySchemes.entries) {
      final camelName = sanitizeFieldName(entry.key);
      final className = '${sanitizeClassName(entry.key)}Security';
      buf.writeln('  final $className? $camelName;');
    }

    buf.writeln('  final ApiErrorInterceptor? errorHandler;');
    buf.writeln('  final List<Interceptor>? interceptors;');
    buf.writeln('  final Dio _dio;');
    buf.writeln('  bool _initialized = false;');
    buf.writeln();

    buf.writeln(
        '  void _addInterceptor(Interceptor interceptor) => _dio.interceptors.add(interceptor);');
    buf.writeln(
        '  void _addInterceptors(List<Interceptor> interceptors) => _dio.interceptors.addAll(interceptors);');
    buf.writeln();

    buf.writeln('  Dio get dio {');
    buf.writeln('    if (!_initialized) {');
    buf.writeln('      _initialized = true;');
    buf.writeln(
        '      if (errorHandler != null) { _addInterceptor(errorHandler!); }');
    for (final entry in securitySchemes.entries) {
      final camelName = sanitizeFieldName(entry.key);
      buf.writeln('      final ${camelName}Copy = $camelName;');
      buf.writeln(
          '      if (${camelName}Copy != null) { _addInterceptor(${camelName}Copy.createInterceptor()); }');
    }
    buf.writeln(
        '      if (interceptors != null) { _addInterceptors(interceptors!); }');
    buf.writeln('    }');
    buf.writeln('    return _dio;');
    buf.writeln('  }');
    buf.writeln();

    for (final tag in operationsByTag.keys) {
      final fieldName = sanitizeFieldName(tag);
      final className = '${sanitizeClassName(tag)}Api';
      buf.writeln(
          '  $className get $fieldName => $className(dio: dio, baseUrl: baseUrl);');
    }

    buf.writeln('}');

    return GeneratedFile(
      path: 'lib/src/api/api_client.dart',
      content: buf.toString(),
    );
  }

  static void _generateComputeDeserializer(
      StringBuffer buf, IrOperation op, String className) {
    final funcName = 'deserialize${sanitizeClassName(op.operationId)}';
    buf.writeln(
        '$className $funcName(({int statusCode, dynamic data}) args) {');
    buf.writeln('  final (:statusCode, :data) = args;');
    buf.writeln('  return switch (statusCode) {');

    for (final resp in op.responses) {
      final status = resp.statusCode;
      if (status == 'default') continue;

      final variantName = '${className}Http$status';
      final mt = resp.content.values.firstOrNull;
      final schema = mt?.schema;

      if (schema != null) {
        buf.writeln(
            '    $status => $variantName(${_fromJsonExpr('data', schema)}),');
      } else {
        buf.writeln('    $status => const $variantName(),');
      }
    }

    buf.writeln(
        '    _ => throw FormatException(\'Unknown status code: \$statusCode\', data),');
    buf.writeln('  };');
    buf.writeln('}');
  }

  static bool _needsToJson(IrSchema? schema) {
    if (schema == null) return false;
    switch (schema) {
      case IrObjectSchema():
        return true;
      case IrRefSchema():
        return true;
      case IrEnumSchema():
        return true;
      case IrUnionSchema():
        return true;
      case IrListSchema():
        return _needsToJson(schema.items);
      case IrMapSchema():
        return _needsToJson(schema.values);
      default:
        return false;
    }
  }
}
