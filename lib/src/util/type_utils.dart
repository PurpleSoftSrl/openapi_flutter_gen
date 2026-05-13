import '../ir/ir.dart';

String dartTypeFromPrimitive(IrPrimitiveType type, {bool nullable = false}) {
  final base = switch (type) {
    IrPrimitiveType.string => 'String',
    IrPrimitiveType.integer => 'int',
    IrPrimitiveType.number => 'double',
    IrPrimitiveType.boolean => 'bool',
    IrPrimitiveType.dateTime => 'DateTime',
    IrPrimitiveType.date => 'DateTime',
    IrPrimitiveType.uri => 'Uri',
    IrPrimitiveType.binary => 'Uint8List',
    IrPrimitiveType.base64 => 'String',
    IrPrimitiveType.any => 'Object',
  };
  return nullable ? '$base?' : base;
}

String schemaToDartType(IrSchema schema) {
  switch (schema) {
    case IrPrimitiveSchema():
      return dartTypeFromPrimitive(schema.type, nullable: schema.isNullable);
    case IrObjectSchema():
      return schema.isNullable ? '${schema.name}?' : schema.name;
    case IrEnumSchema():
      return schema.name;
    case IrUnionSchema():
      return schema.isNullable ? '${schema.name}?' : schema.name;
    case IrListSchema():
      final inner = schemaToDartType(schema.items);
      final base = 'List<$inner>';
      return schema.isNullable ? '$base?' : base;
    case IrMapSchema():
      final inner = schemaToDartType(schema.values);
      final base = 'Map<String, $inner>';
      return schema.isNullable ? '$base?' : base;
    case IrRefSchema():
      return schema.refName;
  }
}

String schemaToJsonType(IrSchema schema) {
  switch (schema) {
    case IrPrimitiveSchema():
      return switch (schema.type) {
        IrPrimitiveType.string || IrPrimitiveType.base64 => 'String',
        IrPrimitiveType.integer => 'int',
        IrPrimitiveType.number => 'double',
        IrPrimitiveType.boolean => 'bool',
        IrPrimitiveType.any => 'Object',
        _ => 'String',
      };
    case IrObjectSchema():
      return 'Map<String, dynamic>';
    case IrEnumSchema():
      return schema.enumType == IrPrimitiveType.integer ? 'int' : 'String';
    case IrUnionSchema():
      return 'Map<String, dynamic>';
    case IrListSchema():
      return 'List<dynamic>';
    case IrMapSchema():
      return 'Map<String, dynamic>';
    case IrRefSchema():
      if (schema.resolved != null) return schemaToJsonType(schema.resolved!);
      return 'Map<String, dynamic>';
  }
}

String schemaToSerializeExpr(String valueExpr, IrSchema schema) {
  switch (schema) {
    case IrPrimitiveSchema():
      return valueExpr;
    case IrObjectSchema():
      return '$valueExpr.toJson()';
    case IrEnumSchema():
      if (schema.enumType == IrPrimitiveType.integer) {
        return '$valueExpr.index';
      }
      return '$valueExpr.name';
    case IrUnionSchema():
      return '$valueExpr.toJson()';
    case IrListSchema():
      final itemSchema = schema.items;
      if (itemSchema is IrObjectSchema) {
        return '$valueExpr.map((e) => e.toJson()).toList()';
      }
      if (itemSchema is IrEnumSchema) {
        return '$valueExpr.map((e) => e.name).toList()';
      }
      return valueExpr;
    case IrMapSchema():
      final valSchema = schema.values;
      if (valSchema is IrObjectSchema) {
        return '$valueExpr.map((k, v) => MapEntry(k, v.toJson()))';
      }
      return valueExpr;
    case IrRefSchema():
      if (schema.resolved != null) return schemaToSerializeExpr(valueExpr, schema.resolved!);
      return '$valueExpr.toJson()';
  }
}

String schemaToDeserializeExpr(String valueExpr, IrSchema schema) {
  switch (schema) {
    case IrPrimitiveSchema():
      return switch (schema.type) {
        IrPrimitiveType.integer => '($valueExpr as num).toInt()',
        IrPrimitiveType.number => '($valueExpr as num).toDouble()',
        IrPrimitiveType.dateTime => 'DateTime.parse($valueExpr as String)',
        IrPrimitiveType.date => 'DateTime.parse($valueExpr as String)',
        _ => '$valueExpr as ${dartTypeFromPrimitive(schema.type)}',
      };
    case IrObjectSchema():
      return '${schema.name}.fromJson($valueExpr as Map<String, dynamic>)';
    case IrEnumSchema():
      if (schema.enumType == IrPrimitiveType.integer) {
        return '${schema.name}.values[($valueExpr as num).toInt()]';
      }
      return '${schema.name}.values.byName($valueExpr as String)';
    case IrUnionSchema():
      return '${schema.name}.fromJson($valueExpr as Map<String, dynamic>)';
    case IrListSchema():
      final itemSchema = schema.items;
      if (itemSchema is IrObjectSchema) {
        return '($valueExpr as List<dynamic>).map((e) => ${itemSchema.name}.fromJson(e as Map<String, dynamic>)).toList()';
      }
      if (itemSchema is IrEnumSchema) {
        return '($valueExpr as List<dynamic>).map((e) => ${itemSchema.name}.values.byName(e as String)).toList()';
      }
      if (itemSchema is IrPrimitiveSchema && itemSchema.type == IrPrimitiveType.dateTime) {
        return '($valueExpr as List<dynamic>).map((e) => DateTime.parse(e as String)).toList()';
      }
      return '($valueExpr as List<dynamic>).cast<${dartTypeFromPrimitive((schema.items as IrPrimitiveSchema).type)}>()';
    case IrMapSchema():
      final valSchema = schema.values;
      if (valSchema is IrObjectSchema) {
        return '($valueExpr as Map<String, dynamic>).map((k, v) => MapEntry(k, ${valSchema.name}.fromJson(v as Map<String, dynamic>)))';
      }
      return '$valueExpr as Map<String, ${dartTypeFromPrimitive((valSchema as IrPrimitiveSchema).type)}>';
    case IrRefSchema():
      if (schema.resolved != null) return schemaToDeserializeExpr(valueExpr, schema.resolved!);
      return '${schema.refName}.fromJson($valueExpr as Map<String, dynamic>)';
  }
}
