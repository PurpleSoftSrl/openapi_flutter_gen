import '../../ir/ir.dart';
import '../../util/type_utils.dart';
import 'naming.dart';

class ModelGenerator {
  static GeneratedFile generate(IrSchema schema,
      {required String packageName, String? schemaName}) {
    return switch (schema) {
      IrObjectSchema() => _generateObject(schema, packageName: packageName),
      IrEnumSchema() => _generateEnum(schema, packageName: packageName),
      IrUnionSchema() => _generateUnion(schema, packageName: packageName),
      IrPrimitiveSchema() => _generatePrimitive(schema,
          schemaName: schemaName!, packageName: packageName),
      IrListSchema() => _generateObjectAlias(schema,
          schemaName: schemaName!, packageName: packageName),
      IrRefSchema() =>
        throw UnimplementedError('Ref schemas should be resolved'),
      _ => throw UnimplementedError('Unexpected schema type: $schema'),
    };
  }

  static GeneratedFile _generatePrimitive(IrPrimitiveSchema schema,
      {required String schemaName, required String packageName}) {
    final className = sanitizeClassName(schemaName);
    final dartType = dartTypeFromPrimitive(schema.type);
    final buf = StringBuffer(generateFileHeader());
    buf.writeln('/// Named type for `$className` from the SumUp API spec.');
    buf.writeln('typedef $className = $dartType;');
    return GeneratedFile(
      path: 'lib/src/models/${className.toLowerCase()}.dart',
      content: buf.toString(),
    );
  }

  static GeneratedFile _generateObjectAlias(IrListSchema schema,
      {required String schemaName, required String packageName}) {
    final className = sanitizeClassName(schemaName);
    final itemType = schemaToDartType(schema.items);
    final importName = _schemaImportName(schema.items);
    final buf = StringBuffer(generateFileHeader());
    if (importName != null) {
      buf.writeln("import '${importName.toLowerCase()}.dart';");
      buf.writeln();
    }
    buf.writeln('/// List wrapper for `$className` from the SumUp API spec.');
    buf.writeln('typedef $className = List<$itemType>;');
    return GeneratedFile(
      path: 'lib/src/models/${className.toLowerCase()}.dart',
      content: buf.toString(),
    );
  }

  static GeneratedFile _generateObject(IrObjectSchema schema,
      {required String packageName}) {
    final buf = StringBuffer(generateFileHeader());

    final allProps = <IrProperty>[];

    for (final inline in schema.allOfInline) {
      for (final prop in inline.properties) {
        allProps.add(prop);
      }
    }

    allProps.addAll(schema.properties);

    final imports = <String>{};

    var needsTypedData = false;
    for (final prop in allProps) {
      final importName = _propertyImportName(prop.schema);
      if (importName != null && importName != schema.name) {
        imports.add(importName);
      }
      if (prop.schema is IrPrimitiveSchema &&
          (prop.schema as IrPrimitiveSchema).type == IrPrimitiveType.binary) {
        needsTypedData = true;
      }
    }

    if (needsTypedData) {
      buf.writeln('import \'dart:typed_data\';');
      buf.writeln('import \'package:dio/dio.dart\';');
    }
    for (final imp in imports.toList()..sort()) {
      buf.writeln('import \'${imp.toLowerCase()}.dart\';');
    }

    buf.writeln();

    final className = sanitizeClassName(schema.name);

    // Emit dartdoc from OpenAPI description
    final desc = schema.description;
    if (desc != null && desc.isNotEmpty) {
      for (final line in desc.split('\n')) {
        buf.writeln('/// ${line.trim()}');
      }
    } else {
      buf.writeln('/// Object model for `$className` from the SumUp API spec.');
    }
    buf.writeln('class $className {');
    if (allProps.isEmpty) {
      buf.writeln('  const $className();');
    } else {
      buf.writeln('  const $className({');

      for (final prop in allProps) {
        final isRequired = prop.isRequired && !prop.isNullable;
        final defaultValue = _defaultValueFor(prop);
        final defStr = defaultValue != null ? ' = $defaultValue' : '';
        buf.write('    ');
        if (isRequired && defaultValue == null) {
          buf.writeln('required this.${sanitizeFieldName(prop.name)},');
        } else {
          buf.writeln('this.${sanitizeFieldName(prop.name)}$defStr,');
        }
      }

      buf.writeln('  });');
    }
    buf.writeln();

    for (final prop in allProps) {
      final typeStr = _propertyDartType(prop);
      final fieldName = sanitizeFieldName(prop.name);
      buf.writeln('  final $typeStr $fieldName;');
    }
    buf.writeln();
    _generateFromJson(buf, allProps, className, schema);
    _generateToJson(buf, allProps, className);
    _generateCopyWith(buf, allProps, className);
    _generateEquality(buf, allProps, className);
    _generateToString(buf, allProps, className);

    if (needsTypedData) {
      _generateToFormData(buf, allProps, className);
    }

    buf.writeln('}');
    return GeneratedFile(
      path:
          'lib/src/models/${sanitizeClassName(schema.name).toLowerCase()}.dart',
      content: buf.toString(),
    );
  }

  static void _generateToFormData(
      StringBuffer buf, List<IrProperty> allProps, String className) {
    buf.writeln();
    buf.writeln('  FormData toFormData() {');
    buf.writeln('    final fd = FormData();');
    for (final prop in allProps) {
      final fieldName = sanitizeFieldName(prop.name);
      final jsonKey = prop.jsonKey ?? prop.name;
      final schema = prop.schema;
      final isRequiredAndNonNullable = prop.isRequired && !prop.isNullable;
      if (schema is IrPrimitiveSchema &&
          schema.type == IrPrimitiveType.binary) {
        if (isRequiredAndNonNullable) {
          buf.writeln(
              '    fd.files.add(MapEntry(\'$jsonKey\', MultipartFile.fromBytes(');
          buf.writeln('      $fieldName, filename: \'$jsonKey\',');
          buf.writeln('    )));');
        } else {
          buf.writeln('    if ($fieldName != null) {');
          buf.writeln('      final bytesCopy = $fieldName;');
          buf.writeln(
              '      fd.files.add(MapEntry(\'$jsonKey\', MultipartFile.fromBytes(');
          buf.writeln('        bytesCopy!, filename: \'$jsonKey\',');
          buf.writeln('      )));');
          buf.writeln('    }');
        }
      } else if (isRequiredAndNonNullable) {
        buf.writeln(
            '    fd.fields.add(MapEntry(\'$jsonKey\', $fieldName.toString()));');
      } else {
        buf.writeln('    if ($fieldName != null) {');
        buf.writeln(
            '      fd.fields.add(MapEntry(\'$jsonKey\', $fieldName.toString()));');
        buf.writeln('    }');
      }
    }
    buf.writeln('    return fd;');
    buf.writeln('  }');
  }

  static void _generateFromJson(StringBuffer buf, List<IrProperty> allProps,
      String className, IrObjectSchema schema) {
    buf.writeln('  /// Creates an instance from a JSON map.');
    buf.writeln('  factory $className.fromJson(Map<String, dynamic> json) {');
    buf.writeln('    return ${allProps.isEmpty ? "const " : ""}$className(');

    final sourceProps = allProps.toList();

    for (int i = 0; i < sourceProps.length; i++) {
      final prop = sourceProps[i];
      final fieldName = sanitizeFieldName(prop.name);
      final jsonKey = prop.jsonKey ?? prop.name;

      if (prop.isRequired && !prop.isNullable) {
        buf.writeln(
            '      $fieldName: ${_fromJsonExpr("json['$jsonKey']", prop.schema)},');
      } else {
        buf.writeln('      $fieldName: json[\'$jsonKey\'] != null');
        buf.writeln(
            '          ? ${_fromJsonExpr("json['$jsonKey']", prop.schema)}');
        buf.writeln('          : null,');
      }
    }

    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln();
  }

  static void _generateToJson(
      StringBuffer buf, List<IrProperty> allProps, String className) {
    buf.writeln('  Map<String, dynamic> toJson() {');
    buf.writeln('    return {');

    for (final prop in allProps) {
      final fieldName = sanitizeFieldName(prop.name);
      final jsonKey = prop.jsonKey ?? prop.name;

      if (prop.isRequired && !prop.isNullable) {
        buf.writeln(
            '      \'$jsonKey\': ${_toJsonExpr(fieldName, prop.schema)},');
      } else if (prop.isRequired && prop.isNullable) {
        buf.writeln(
            '      \'$jsonKey\': ${_toJsonExprNullable(fieldName, prop.schema)},');
      } else {
        buf.writeln(
            '      if ($fieldName != null) \'$jsonKey\': ${_toJsonExpr('$fieldName!', prop.schema)},');
      }
    }

    buf.writeln('    };');
    buf.writeln('  }');
    buf.writeln();
  }

  static void _generateCopyWith(
      StringBuffer buf, List<IrProperty> allProps, String className) {
    if (allProps.isEmpty) {
      buf.writeln('  $className copyWith() {');
      buf.writeln('    return this;');
      buf.writeln('  }');
      buf.writeln();
      return;
    }

    buf.writeln('  $className copyWith({');

    for (final prop in allProps) {
      var rawType = schemaToDartType(prop.schema);
      if (rawType.endsWith('?'))
        rawType = rawType.substring(0, rawType.length - 1);
      buf.writeln('    $rawType? ${sanitizeFieldName(prop.name)},');
    }

    buf.writeln('  }) {');
    if (allProps.isNotEmpty) {
      buf.write('    if (');
      buf.write(allProps
          .map((p) => '${sanitizeFieldName(p.name)} == null')
          .join(' && '));
      buf.writeln(') { return this; }');
      buf.writeln();
    }
    buf.writeln('    return ${allProps.isEmpty ? "const " : ""}$className(');

    for (final prop in allProps) {
      final fieldName = sanitizeFieldName(prop.name);
      if (allProps.length == 1) {
        buf.writeln('      ${fieldName}: ${fieldName},');
      } else {
        buf.writeln('      ${fieldName}: ${fieldName} ?? this.${fieldName},');
      }
    }

    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln();
  }

  static void _generateEquality(
      StringBuffer buf, List<IrProperty> allProps, String className) {
    buf.writeln('  @override');
    buf.writeln('  bool operator ==(Object other) {');
    buf.writeln('    if (identical(this, other)) { return true; }');
    if (allProps.length >= 20) {
      buf.writeln('    if (other is! $className) { return false; }');
      buf.writeln('    if (hashCode != other.hashCode) { return false; }');
    } else {
      buf.writeln('    if (other is! $className) { return false; }');
      buf.write('    return ');
    }
    if (allProps.length < 20) {
      if (allProps.isEmpty) {
        buf.writeln('true;');
      } else {
        for (int i = 0; i < allProps.length; i++) {
          final prop = allProps[i];
          final fieldName = sanitizeFieldName(prop.name);
          if (i == 0) {
            buf.writeln('$fieldName == other.$fieldName');
          } else {
            buf.writeln('        && $fieldName == other.$fieldName');
          }
        }
        buf.writeln(';');
      }
    } else {
      buf.write('    return ');
      for (int i = 0; i < allProps.length; i++) {
        final prop = allProps[i];
        final fieldName = sanitizeFieldName(prop.name);
        if (i == 0) {
          buf.writeln('$fieldName == other.$fieldName');
        } else {
          buf.writeln('        && $fieldName == other.$fieldName');
        }
      }
      buf.writeln(';');
    }
    buf.writeln('  }');
    buf.writeln();

    buf.writeln('  @override');
    buf.write('  int get hashCode => ');
    if (allProps.isEmpty) {
      buf.writeln('runtimeType.hashCode;');
    } else if (allProps.length == 1) {
      buf.writeln('${sanitizeFieldName(allProps[0].name)}.hashCode;');
    } else {
      final propNames = allProps.map((p) => sanitizeFieldName(p.name)).toList();
      if (propNames.length <= 20) {
        buf.write('Object.hash(');
        buf.write(propNames.join(', '));
        buf.writeln(');');
      } else {
        // Split into chunks of at most 20, ensuring no chunk has exactly 1 element
        var remaining = propNames.toList();
        final chunkExprs = <String>[];
        while (remaining.isNotEmpty) {
          var take = remaining.length > 20 ? 20 : remaining.length;
          // If taking 20 leaves exactly 1 behind, take 19 instead
          if (take == 20 && remaining.length - take == 1) {
            take = 19;
          }
          final chunk = remaining.take(take).toList();
          remaining = remaining.skip(take).toList();
          chunkExprs.add('Object.hash(${chunk.join(', ')})');
        }
        buf.write('Object.hash(');
        buf.write(chunkExprs.join(', '));
        buf.writeln(');');
      }
    }
    buf.writeln();
  }

  static void _generateToString(
      StringBuffer buf, List<IrProperty> allProps, String className) {
    buf.writeln('  @override');
    buf.write('  String toString() => \'$className(');
    buf.write(allProps
        .map((p) =>
            '${sanitizeFieldName(p.name)}=\$${sanitizeFieldName(p.name)}')
        .join(', '));
    buf.writeln(')\';');
  }

  static GeneratedFile _generateEnum(IrEnumSchema schema,
      {required String packageName}) {
    final buf = StringBuffer(generateFileHeader());
    buf.writeln('// ignore_for_file: constant_identifier_names');
    buf.writeln();
    final className = sanitizeClassName(schema.name);

    final typeStr =
        schema.enumType == IrPrimitiveType.string ? 'String' : 'int';

    final schemaValues = schema.values;
    final desc = schema.description;
    if (desc != null && desc.isNotEmpty) {
      for (final line in desc.split('\n')) {
        buf.writeln('/// ${line.trim()}');
      }
    } else {
      buf.writeln('/// Enum for `$className` from the SumUp API spec.');
    }
    buf.writeln('enum $className {');

    for (int i = 0; i < schemaValues.length; i++) {
      final value = schemaValues[i];
      final comma = i < schemaValues.length - 1 ? ',' : ';';
      if (schema.enumType == IrPrimitiveType.string &&
          value.jsonValue != null) {
        buf.writeln(
            '  ${safeDartName(value.name)}(\'${value.jsonValue}\')$comma');
      } else {
        buf.writeln('  ${safeDartName(value.name)}$comma');
      }
    }

    buf.writeln();

    if (schema.enumType == IrPrimitiveType.string) {
      buf.writeln('  const $className(this.value);');
      buf.writeln('  final String value;');
      buf.writeln();
    }

    buf.writeln('  static $className fromJson($typeStr json) {');
    if (schema.enumType == IrPrimitiveType.string) {
      buf.writeln('    return $className.values.firstWhere(');
      buf.writeln('      (e) => e.name == json || e.value == json,');
      buf.writeln(
          '      orElse: () => throw ArgumentError(\'Unknown $className: \$json\'),');
      buf.writeln('    );');
    } else {
      buf.writeln('    return $className.values[(json as num).toInt()];');
    }
    buf.writeln('  }');
    buf.writeln();

    buf.writeln(
        '  $typeStr toJson() => ${schema.enumType == IrPrimitiveType.string ? 'value' : 'index'};');

    buf.writeln('}');

    return GeneratedFile(
      path:
          'lib/src/models/${sanitizeClassName(schema.name).toLowerCase()}.dart',
      content: buf.toString(),
    );
  }

  static GeneratedFile _generateUnion(IrUnionSchema schema,
      {required String packageName}) {
    final buf = StringBuffer(generateFileHeader());
    buf.writeln('// ignore_for_file: unused_import, unnecessary_cast');
    buf.writeln();
    final className = sanitizeClassName(schema.name);

    final imports = <String>{};
    var needsTypedData = false;
    for (final variant in schema.variants) {
      final importName = _schemaImportName(variant.schema);
      if (importName != null && importName != className) {
        imports.add(importName);
      }
      if (variant.schema is IrPrimitiveSchema &&
          (variant.schema as IrPrimitiveSchema).type ==
              IrPrimitiveType.binary) {
        needsTypedData = true;
      }
    }

    if (needsTypedData) {
      buf.writeln("import 'dart:typed_data';");
    }
    for (final imp in imports.toList()..sort()) {
      buf.writeln("import '${imp.toLowerCase()}.dart';");
    }
    buf.writeln();

    final desc = schema.description;
    if (desc != null && desc.isNotEmpty) {
      for (final line in desc.split('\n')) {
        buf.writeln('/// ${line.trim()}');
      }
    }
    buf.writeln('sealed class $className {');
    buf.writeln('  const $className();');
    buf.writeln();

    _generateUnionFromJson(buf, schema);
    buf.writeln();

    if (!schema.isAnyOf && schema.discriminatorProperty == null) {
      buf.writeln('  Map<String, dynamic> toJson() => switch (this) {');
      for (final variant in schema.variants) {
        final discValue = variant.discriminatorValue ?? '';
        final varClassName = _variantClassName(
            className, discValue, schema.variants.indexOf(variant));
        buf.writeln('    $varClassName v => v.toJson(),');
      }
      buf.writeln('  };');
    } else {
      buf.writeln('  Map<String, dynamic> toJson();');
    }

    buf.writeln('}');
    buf.writeln();

    for (int i = 0; i < schema.variants.length; i++) {
      _generateUnionVariant(buf, i, schema);
      buf.writeln();
    }

    if (schema.discriminatorProperty != null) {
      final unknownName = '${className}Unknown';
      buf.writeln('class _$unknownName extends $className {');
      buf.writeln('  const _$unknownName(this.data);');
      buf.writeln('  final Map<String, dynamic> data;');
      buf.writeln();
      buf.writeln('  /// Creates an unknown variant instance from a JSON map.');
      buf.writeln(
          '  factory _$unknownName.fromJson(Map<String, dynamic> json) => _$unknownName(json);');
      buf.writeln();
      buf.writeln('  @override');
      buf.writeln('  Map<String, dynamic> toJson() => data;');
      buf.writeln('}');
      buf.writeln();
    }

    return GeneratedFile(
      path:
          'lib/src/models/${sanitizeClassName(schema.name).toLowerCase()}.dart',
      content: buf.toString(),
    );
  }

  static void _generateUnionFromJson(StringBuffer buf, IrUnionSchema schema) {
    final className = sanitizeClassName(schema.name);
    final discriminator = schema.discriminatorProperty;

    buf.writeln('  factory $className.fromJson(Map<String, dynamic> json) {');

    if (discriminator != null) {
      buf.writeln('    return switch (json[\'$discriminator\'] as String?) {');
      for (final variant in schema.variants) {
        final discValue = variant.discriminatorValue ?? '';
        final varClassName = _variantClassName(
            className, discValue, schema.variants.indexOf(variant));
        buf.writeln('      \'$discValue\' => $varClassName.fromJson(json),');
      }
      buf.writeln('      _ => _${className}Unknown.fromJson(json),');
      buf.writeln('    };');
    } else {
      for (int i = 0; i < schema.variants.length; i++) {
        final variant = schema.variants[i];
        final discValue = variant.discriminatorValue ?? '';
        final varClassName = _variantClassName(className, discValue, i);
        buf.writeln(
            '    try { return $varClassName.fromJson(json); } catch (_) {}');
      }
      buf.writeln(
          "    throw FormatException('Cannot decode $className', json);");
    }

    buf.writeln('  }');
  }

  static void _generateUnionVariant(
      StringBuffer buf, int index, IrUnionSchema schema) {
    final className = sanitizeClassName(schema.name);
    final variant = schema.variants[index];
    final discValue = variant.discriminatorValue ?? '';
    final varClassName = _variantClassName(className, discValue, index);

    final variantSchema = variant.schema;
    if (variantSchema is IrRefSchema) {
      final refName = sanitizeClassName(variantSchema.refName);
      buf.writeln('/// Sealed variant for `$varClassName` in `$className`.');
      buf.writeln('class $varClassName extends $className {');
      buf.writeln('  const $varClassName(this.value);');
      buf.writeln('  final $refName value;');
      buf.writeln();
      buf.writeln('  /// Creates a variant instance from a JSON map.');
      buf.writeln(
          '  factory $varClassName.fromJson(Map<String, dynamic> json) => $varClassName($refName.fromJson(json));');
      buf.writeln();
      buf.writeln('  @override');
      buf.writeln('  Map<String, dynamic> toJson() => value.toJson();');
      buf.writeln('}');
    } else if (variantSchema is IrObjectSchema) {
      buf.writeln('/// Sealed variant for `$varClassName` in `$className`.');
      buf.writeln('class $varClassName extends $className {');
      buf.writeln('  const $varClassName({');
      for (final prop in variantSchema.properties) {
        final isReq = prop.isRequired && !prop.isNullable;
        buf.writeln(
            '    ${isReq ? 'required ' : ''}this.${sanitizeFieldName(prop.name)},');
      }
      buf.writeln('  });');

      for (final prop in variantSchema.properties) {
        buf.writeln(
            '  final ${schemaToDartType(prop.schema)} ${sanitizeFieldName(prop.name)};');
      }
      buf.writeln();

      buf.writeln(
          '  factory $varClassName.fromJson(Map<String, dynamic> json) => $varClassName(');
      for (final prop in variantSchema.properties) {
        final fieldName = sanitizeFieldName(prop.name);
        final jsonKey = prop.jsonKey ?? prop.name;
        buf.writeln(
            '    $fieldName: ${_fromJsonExpr('json[\'$jsonKey\']', prop.schema)},');
      }
      buf.writeln('  );');
      buf.writeln();

      buf.writeln('  @override');
      buf.writeln('  Map<String, dynamic> toJson() => {');
      for (final prop in variantSchema.properties) {
        final fieldName = sanitizeFieldName(prop.name);
        final jsonKey = prop.jsonKey ?? prop.name;
        buf.writeln(
            '    \'$jsonKey\': ${_toJsonExpr(fieldName, prop.schema)},');
      }
      buf.writeln('  };');

      buf.writeln('}');
    } else if (variantSchema is IrPrimitiveSchema) {
      final typeStr = schemaToDartType(variantSchema);
      buf.writeln('/// Sealed variant for `$varClassName` in `$className`.');
      buf.writeln('class $varClassName extends $className {');
      buf.writeln('  const $varClassName(this.value);');
      buf.writeln('  final $typeStr value;');
      buf.writeln();
      buf.writeln('  /// Creates a variant from deserialized JSON.');
      buf.writeln(
          '  factory $varClassName.fromJson(dynamic json) => $varClassName(${_fromJsonExpr('json', variantSchema)});');
      buf.writeln();
      buf.writeln('  @override');
      buf.writeln(
          '  Map<String, dynamic> toJson() => {\'value\': ${_toJsonExpr('value', variantSchema)}};');
      buf.writeln('}');
    } else if (variantSchema is IrListSchema) {
      final typeStr = schemaToDartType(variantSchema);
      final fromExpr = _fromJsonExpr('json', variantSchema);
      final toExpr = _toJsonExpr('value', variantSchema);
      buf.writeln('/// Sealed variant for `$varClassName` in `$className`.');
      buf.writeln('class $varClassName extends $className {');
      buf.writeln('  const $varClassName(this.value);');
      buf.writeln('  final $typeStr value;');
      buf.writeln();
      buf.writeln('  /// Creates a list variant from deserialized JSON.');
      buf.writeln(
          '  factory $varClassName.fromJson(dynamic json) => $varClassName($fromExpr);');
      buf.writeln();
      buf.writeln('  @override');
      buf.writeln('  Map<String, dynamic> toJson() => {\'value\': $toExpr};');
      buf.writeln('}');
    } else if (variantSchema is IrEnumSchema) {
      final typeStr = schemaToDartType(variantSchema);
      buf.writeln('/// Sealed variant for `$varClassName` in `$className`.');
      buf.writeln('class $varClassName extends $className {');
      buf.writeln('  const $varClassName(this.value);');
      buf.writeln('  final $typeStr value;');
      buf.writeln();
      buf.writeln('  /// Creates an enum variant from deserialized JSON.');
      buf.writeln(
          '  factory $varClassName.fromJson(dynamic json) => $varClassName(${_fromJsonExpr('json', variantSchema)});');
      buf.writeln();
      buf.writeln('  @override');
      buf.writeln(
          '  Map<String, dynamic> toJson() => {\'value\': ${_toJsonExpr('value', variantSchema)}};');
      buf.writeln('}');
    }
  }

  static String _variantClassName(
      String parentName, String discValue, int index) {
    if (discValue.isEmpty) return '${parentName}Variant$index';
    final disc = sanitizeClassName(discValue);
    if (disc.startsWith(parentName)) return '${disc}Variant$index';
    return '${parentName}${disc}Variant$index';
  }

  static String _propertyDartType(IrProperty prop) {
    final baseType = schemaToDartType(prop.schema);
    if (prop.isRequired && !prop.isNullable) return baseType;
    if (baseType.endsWith('?')) return baseType;
    return '$baseType?';
  }

  static String? _propertyImportName(IrSchema schema) {
    return switch (schema) {
      IrObjectSchema() => sanitizeClassName(schema.name),
      IrEnumSchema() => sanitizeClassName(schema.name),
      IrUnionSchema() => sanitizeClassName(schema.name),
      IrRefSchema() => sanitizeClassName(schema.refName),
      IrListSchema() => _propertyImportName(schema.items),
      IrMapSchema() => _propertyImportName(schema.values),
      _ => null,
    };
  }

  static String? _schemaImportName(IrSchema schema) {
    return switch (schema) {
      IrObjectSchema() => sanitizeClassName(schema.name),
      IrEnumSchema() => sanitizeClassName(schema.name),
      IrUnionSchema() => sanitizeClassName(schema.name),
      IrRefSchema() => sanitizeClassName(schema.refName),
      _ => null,
    };
  }

  static String _fromJsonExpr(String expr, IrSchema schema) {
    switch (schema) {
      case IrPrimitiveSchema(type: IrPrimitiveType.integer):
        return '($expr as num).toInt()';
      case IrPrimitiveSchema(type: IrPrimitiveType.number):
        return '($expr as num).toDouble()';
      case IrPrimitiveSchema(type: IrPrimitiveType.dateTime):
        return 'DateTime.parse($expr as String)';
      case IrPrimitiveSchema(type: IrPrimitiveType.date):
        return 'DateTime.parse($expr as String)';
      case IrPrimitiveSchema(type: IrPrimitiveType.uri):
        return 'Uri.parse($expr as String)';
      case IrPrimitiveSchema():
        return '$expr as ${dartTypeFromPrimitive(schema.type)}';
      case IrObjectSchema():
        return '${sanitizeClassName(schema.name)}.fromJson($expr as Map<String, dynamic>)';
      case IrEnumSchema():
        return '${sanitizeClassName(schema.name)}.fromJson($expr as ${schema.enumType == IrPrimitiveType.integer ? 'int' : 'String'})';
      case IrUnionSchema():
        return '${sanitizeClassName(schema.name)}.fromJson($expr as Map<String, dynamic>)';
      case IrRefSchema():
        final ref = sanitizeClassName(schema.refName);
        return '$ref.fromJson($expr as Map<String, dynamic>)';
      case IrListSchema():
        if (schema.items is IrObjectSchema || schema.items is IrRefSchema) {
          final itemName = _propertyImportName(schema.items) ?? 'Object';
          return 'List<$itemName>.generate(($expr as List).length, (i) => $itemName.fromJson(($expr as List)[i] as Map<String, dynamic>), growable: false)';
        }
        if (schema.items is IrEnumSchema) {
          final enumName =
              sanitizeClassName((schema.items as IrEnumSchema).name);
          final enumType =
              (schema.items as IrEnumSchema).enumType == IrPrimitiveType.integer
                  ? 'int'
                  : 'String';
          return 'List<$enumName>.generate(($expr as List).length, (i) => $enumName.fromJson(($expr as List<dynamic>)[i] as $enumType), growable: false)';
        }
        final inner = schemaToDartType(schema.items);
        // A decoded JSON array is a List<dynamic> at runtime; a direct `as List<T>`
        // cast throws even when every element is a T. Use .cast<T>() to re-wrap it.
        return '($expr as List).cast<$inner>()';
      case IrMapSchema():
        final valSchema = schema.values;
        if (valSchema is IrObjectSchema || valSchema is IrRefSchema) {
          final valName = _propertyImportName(valSchema) ?? 'Object';
          return '($expr as Map<String, dynamic>).map((k, v) => MapEntry(k, $valName.fromJson(v)))';
        }
        // Same dynamic-typing issue as primitive lists: re-wrap via .cast<K,V>().
        return '($expr as Map).cast<String, ${schemaToDartType(schema.values)}>()';
    }
  }

  static String _toJsonExpr(String expr, IrSchema schema) {
    switch (schema) {
      case IrObjectSchema():
      case IrRefSchema():
        return '$expr.toJson()';
      case IrEnumSchema():
        return '$expr.toJson()';
      case IrUnionSchema():
        return '$expr.toJson()';
      case IrListSchema():
        if (schema.items is IrObjectSchema || schema.items is IrRefSchema) {
          return '$expr.map((e) => e.toJson()).toList()';
        }
        if (schema.items is IrEnumSchema) {
          return '$expr.map((e) => e.toJson()).toList()';
        }
        return expr;
      case IrMapSchema():
        if (schema.values is IrObjectSchema || schema.values is IrRefSchema) {
          return '$expr.map((k, v) => MapEntry(k, v.toJson()))';
        }
        return expr;
      case IrPrimitiveSchema(
          type: IrPrimitiveType.dateTime || IrPrimitiveType.date
        ):
        return '$expr.toIso8601String()';
      case IrPrimitiveSchema(type: IrPrimitiveType.uri):
        return '$expr.toString()';
      case IrPrimitiveSchema():
        return expr;
    }
  }

  static String _toJsonExprNullable(String expr, IrSchema schema) {
    if (schema is IrPrimitiveSchema) {
      switch (schema.type) {
        case IrPrimitiveType.dateTime:
        case IrPrimitiveType.date:
          return '$expr?.toIso8601String()';
        case IrPrimitiveType.uri:
          return '$expr?.toString()';
        default:
          return expr;
      }
    }
    return '$expr?.toJson()';
  }

  static String? _defaultValueFor(IrProperty prop) {
    if (!prop.isRequired || prop.isNullable) return null;
    final schema = prop.schema;
    if (schema is IrPrimitiveSchema && schema.defaultValue != null) {
      final dv = schema.defaultValue;
      if (schema.type == IrPrimitiveType.string) return '\'$dv\'';
      if (schema.type == IrPrimitiveType.boolean) return '$dv';
      return '$dv';
    }
    return null;
  }
}

class GeneratedFile {
  final String path;
  final String content;
  const GeneratedFile({required this.path, required this.content});
}
