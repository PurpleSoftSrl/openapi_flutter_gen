import 'dart:core';

sealed class IrSchema {
  String? description;
  bool isDeprecated;

  IrSchema({this.description, this.isDeprecated = false});
}

class IrRefSchema extends IrSchema {
  final String refName;
  final IrSchema? resolved;

  IrRefSchema({
    required this.refName,
    this.resolved,
    super.description,
    super.isDeprecated,
  });

  @override
  String toString() => 'IrRefSchema($refName)';
}

class IrObjectSchema extends IrSchema {
  final String name;
  final List<IrProperty> properties;
  final List<IrRefSchema> allOfRefs;
  final List<IrObjectSchema> allOfInline;
  final IrSchema? additionalProperties;
  final String? discriminatorProperty;
  final List<String>? requiredFields;
  final bool isNullable;

  IrObjectSchema({
    required this.name,
    this.properties = const [],
    this.allOfRefs = const [],
    this.allOfInline = const [],
    this.additionalProperties,
    this.discriminatorProperty,
    this.requiredFields,
    this.isNullable = false,
    super.description,
    super.isDeprecated,
  });

  @override
  String toString() => 'IrObjectSchema($name)';
}

class IrEnumSchema extends IrSchema {
  final String name;
  final List<IrEnumValue> values;
  final IrPrimitiveType enumType;

  IrEnumSchema({
    required this.name,
    required this.values,
    this.enumType = IrPrimitiveType.string,
    super.description,
    super.isDeprecated,
  });

  @override
  String toString() => 'IrEnumSchema($name)';
}

class IrEnumValue {
  final String name;
  final String? jsonValue;
  final String? description;

  const IrEnumValue({required this.name, this.jsonValue, this.description});
}

class IrUnionSchema extends IrSchema {
  final String name;
  final List<IrUnionVariant> variants;
  final String? discriminatorProperty;
  final bool isAnyOf;
  final bool isNullable;

  IrUnionSchema({
    required this.name,
    required this.variants,
    this.discriminatorProperty,
    this.isAnyOf = false,
    this.isNullable = false,
    super.description,
    super.isDeprecated,
  });

  @override
  String toString() => 'IrUnionSchema($name, variants: ${variants.length})';
}

class IrUnionVariant {
  final String? discriminatorValue;
  final IrSchema schema;

  const IrUnionVariant({this.discriminatorValue, required this.schema});
}

class IrListSchema extends IrSchema {
  final IrSchema items;
  final bool isNullable;

  IrListSchema({
    required this.items,
    this.isNullable = false,
    super.description,
    super.isDeprecated,
  });

  @override
  String toString() => 'IrListSchema(items: $items)';
}

class IrMapSchema extends IrSchema {
  final IrSchema values;
  final bool isNullable;

  IrMapSchema({
    required this.values,
    this.isNullable = false,
    super.description,
    super.isDeprecated,
  });

  @override
  String toString() => 'IrMapSchema(values: $values)';
}

class IrPrimitiveSchema extends IrSchema {
  final IrPrimitiveType type;
  final String? format;
  final String? pattern;
  final double? minimum;
  final double? maximum;
  final int? minLength;
  final int? maxLength;
  final int? minItems;
  final int? maxItems;
  final bool isNullable;
  final Object? defaultValue;

  IrPrimitiveSchema({
    required this.type,
    this.format,
    this.pattern,
    this.minimum,
    this.maximum,
    this.minLength,
    this.maxLength,
    this.minItems,
    this.maxItems,
    this.isNullable = false,
    this.defaultValue,
    super.description,
    super.isDeprecated,
  });

  @override
  String toString() => 'IrPrimitiveSchema(${type.name})';
}

enum IrPrimitiveType {
  string,
  integer,
  number,
  boolean,
  dateTime,
  date,
  uri,
  binary,
  base64,
  any,
}

class IrProperty {
  final String name;
  final String? jsonKey;
  final IrSchema schema;
  final bool isRequired;
  final bool isNullable;
  final bool isReadOnly;
  final bool isWriteOnly;
  final String? description;
  final Object? defaultValue;

  const IrProperty({
    required this.name,
    this.jsonKey,
    required this.schema,
    this.isRequired = false,
    this.isNullable = false,
    this.isReadOnly = false,
    this.isWriteOnly = false,
    this.description,
    this.defaultValue,
  });
}

class IrOperation {
  final String operationId;
  final String httpMethod;
  final String path;
  final String? summary;
  final String? description;
  final List<IrParameter> parameters;
  final IrRequestBody? requestBody;
  final List<IrResponse> responses;
  final List<String> tags;
  final bool isDeprecated;
  final List<Map<String, List<String>>> security;

  IrOperation({
    required this.operationId,
    required this.httpMethod,
    required this.path,
    this.summary,
    this.description,
    this.parameters = const [],
    this.requestBody,
    this.responses = const [],
    this.tags = const [],
    this.isDeprecated = false,
    this.security = const [],
  });
}

class IrParameter {
  final String name;
  final IrParameterLocation location;
  final IrSchema schema;
  final bool isRequired;
  final String? description;
  final IrEncodingStyle? style;
  final bool explode;

  IrParameter({
    required this.name,
    required this.location,
    required this.schema,
    this.isRequired = false,
    this.description,
    this.style,
    this.explode = true,
  });
}

enum IrParameterLocation { path, query, header, cookie }

enum IrEncodingStyle { simple, label, matrix, form, spaceDelimited, pipeDelimited, deepObject }

class IrRequestBody {
  final Map<String, IrMediaType> content;
  final bool isRequired;
  final String? description;

  IrRequestBody({
    required this.content,
    this.isRequired = false,
    this.description,
  });
}

class IrMediaType {
  final String contentType;
  final IrSchema? schema;

  IrMediaType({required this.contentType, this.schema});
}

class IrResponse {
  final String statusCode;
  final String? description;
  final Map<String, IrMediaType> content;
  final List<IrResponseHeader> headers;

  IrResponse({
    required this.statusCode,
    this.description,
    this.content = const {},
    this.headers = const [],
  });
}

class IrResponseHeader {
  final String name;
  final String? jsonKey;
  final IrSchema schema;
  final bool isRequired;
  final String? description;

  IrResponseHeader({
    required this.name,
    this.jsonKey,
    required this.schema,
    this.isRequired = false,
    this.description,
  });
}

class IrApiDocument {
  final IrApiInfo info;
  final Map<String, IrSchema> schemas;
  final List<IrOperation> operations;
  final Map<String, List<IrOperation>> operationsByTag;
  final List<IrServer> servers;
  final Map<String, IrSecurityScheme> securitySchemes;

  IrApiDocument({
    required this.info,
    this.schemas = const {},
    this.operations = const [],
    this.operationsByTag = const {},
    this.servers = const [],
    this.securitySchemes = const {},
  });
}

class IrApiInfo {
  final String title;
  final String? version;
  final String? description;
  final String? termsOfService;

  IrApiInfo({
    required this.title,
    this.version,
    this.description,
    this.termsOfService,
  });
}

class IrServer {
  final String url;
  final String? description;
  final Map<String, IrServerVariable> variables;

  IrServer({
    required this.url,
    this.description,
    this.variables = const {},
  });
}

class IrServerVariable {
  final String defaultValue;
  final List<String>? enumValues;
  final String? description;

  IrServerVariable({
    required this.defaultValue,
    this.enumValues,
    this.description,
  });
}

class IrSecurityScheme {
  final String name;
  final String type;
  final String? scheme;
  final String? bearerFormat;
  final String? description;

  IrSecurityScheme({
    required this.name,
    required this.type,
    this.scheme,
    this.bearerFormat,
    this.description,
  });
}
