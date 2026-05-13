import '../ir/ir.dart';
import 'loader.dart';

class OpenApiSpecParser {
  final Map<String, dynamic> _doc;
  final Map<String, IrSchema> _schemas = {};
  final Set<String> _resolving = {};
  late final Map<String, dynamic> _components;
  late final Map<String, dynamic> _schemasRaw;

  OpenApiSpecParser(this._doc) {
    _components = getMapOrEmpty(_doc, 'components');
    _schemasRaw = getMapOrEmpty(_components, 'schemas');
  }

  IrApiDocument parse() {
    final info = _parseInfo();
    _parseAllSchemas();
    final servers = _parseServers();
    final securitySchemes = _parseSecuritySchemes();
    final operations = _parseOperations();
    _collectInlineSchemas(operations);
    final byTag = <String, List<IrOperation>>{};
    for (final op in operations) {
      for (final tag in op.tags) {
        byTag.putIfAbsent(tag, () => []).add(op);
      }
    }
    return IrApiDocument(
      info: info,
      schemas: Map.unmodifiable(_schemas),
      operations: operations,
      operationsByTag: Map.unmodifiable(byTag),
      servers: servers,
      securitySchemes: Map.unmodifiable(securitySchemes),
    );
  }

  IrApiInfo _parseInfo() {
    final info = getMapOrEmpty(_doc, 'info');
    return IrApiInfo(
      title: getString(info, 'title') ?? 'Api',
      version: getString(info, 'version'),
      description: getString(info, 'description'),
      termsOfService: getString(info, 'termsOfService'),
    );
  }

  void _parseAllSchemas() {
    _extractInlineSchemasFromRaw();
    
    for (final entry in _schemasRaw.entries) {
      final name = entry.key;
      final schemaJson = entry.value;
      if (schemaJson is! Map<String, dynamic>) continue;
      if (!_schemas.containsKey(name)) {
        _schemas[name] = _parseSchema(name, schemaJson);
      }
    }
    // Resolve refs that were created before their schemas were extracted
    for (final entry in _schemasRaw.entries) {
      final name = entry.key;
      if (!_schemas.containsKey(name)) {
        _schemas[name] = _parseSchema(name, entry.value as Map<String, dynamic>);
      }
    }
    for (final schema in _schemas.values) {
      if (schema is IrObjectSchema) {
        _resolveAllOfRefs(schema);
      }
    }
  }

  void _extractInlineSchemasFromRaw() {
    final toAdd = <String, Map<String, dynamic>>{};
    for (final entry in Map.of(_schemasRaw).entries) {
      if (entry.value is! Map<String, dynamic>) continue;
      final schema = entry.value as Map<String, dynamic>;
      _extractFromSchema(schema, entry.key, toAdd);
    }
    _schemasRaw.addAll(toAdd);
    // Add to _doc directly (not _components which may be a copy from YAML parsing)
    final docComp = _doc['components'] as Map<String, dynamic>?;
    if (docComp != null) {
      final docSchemas = (docComp['schemas'] as Map<String, dynamic>?) ?? {};
      docSchemas.addAll(toAdd);
      docComp['schemas'] = docSchemas;
    }
    if (toAdd.isNotEmpty) _extractInlineSchemasFromRaw();
  }

  void _extractFromSchema(Map<String, dynamic> schema, String parentName,
      Map<String, Map<String, dynamic>> toAdd) {
    final props = schema['properties'];
    if (props is Map<String, dynamic>) {
      for (final propEntry in Map.of(props).entries) {
        if (propEntry.value is! Map<String, dynamic>) continue;
        final prop = propEntry.value as Map<String, dynamic>;
        _extractProperty(prop, props, propEntry.key, parentName, toAdd);
      }
    }
    // Extract from oneOf/anyOf/allOf — items become separate schemas
    for (final key in ['oneOf', 'anyOf', 'allOf']) {
      final list = schema[key];
      if (list is List) {
        for (var i = 0; i < list.length; i++) {
          final item = list[i];
          if (item is! Map<String, dynamic>) continue;
          if (item.containsKey(r'$ref')) continue;
          if (!_isExtractable(item)) continue;
          final inlineName = '${parentName}Inline${i}';
          if (!_schemasRaw.containsKey(inlineName) && !toAdd.containsKey(inlineName)) {
            toAdd[inlineName] = Map.of(item);
            list[i] = {r'$ref': '#/components/schemas/$inlineName'};
          }
        }
      }
    }
    // Also extract from items of array properties
    for (final entry in Map.of(props is Map ? props : <String, dynamic>{}).entries) {
      if (entry.value is! Map<String, dynamic>) continue;
      final prop = entry.value as Map<String, dynamic>;
      final items = prop['items'];
      if (items is Map<String, dynamic> && _isExtractable(items)) {
        final itemsName = '${parentName}${_toPascalCase(entry.key)}Item';
        if (!_schemasRaw.containsKey(itemsName) && !toAdd.containsKey(itemsName)) {
          toAdd[itemsName] = Map.of(items);
          prop['items'] = {r'$ref': '#/components/schemas/$itemsName'};
        }
      }
    }
  }

  void _extractProperty(Map<String, dynamic> prop, Map<String, dynamic> props,
      String propKey, String parentName, Map<String, Map<String, dynamic>> toAdd) {
    final propName = _toPascalCase(propKey);
    final inlineName = '${parentName}$propName';
    if (_isExtractable(prop) &&
        !_schemasRaw.containsKey(inlineName) && !toAdd.containsKey(inlineName) &&
        !_schemasRaw.containsKey(propName)) {
      toAdd[inlineName] = Map.of(prop);
      props[propKey] = {r'$ref': '#/components/schemas/$inlineName'};
    }
  }

  bool _isExtractable(Map<String, dynamic> prop) {
    if (prop.containsKey(r'$ref')) return false;
    if (prop.containsKey('enum')) return true;
    if (prop.containsKey('oneOf')) return true;
    if (prop.containsKey('anyOf')) return true;
    return prop['type'] == 'object' || prop.containsKey('properties');
  }

  IrSchema _parseSchema(String name, Map<String, dynamic> schemaJson) {
    if (_resolving.contains(name)) {
      return IrRefSchema(refName: name);
    }

    if (_schemas.containsKey(name)) {
      return _schemas[name]!;
    }

    _resolving.add(name);

    try {
      if (schemaJson.containsKey(r'$ref')) {
        final ref = schemaJson[r'$ref'] as String;
        final refName = _refToName(ref);
        final resolvedMap = _resolveRef(ref);
        if (resolvedMap != null) {
          final schema = _parseSchema(refName, resolvedMap);
          _resolving.remove(name);
          return schema;
        }
        _resolving.remove(name);
        return IrRefSchema(refName: refName);
      }

      final type = getString(schemaJson, 'type');
      final hasEnum = schemaJson.containsKey('enum');

      if (hasEnum) {
        return _parseEnum(name, schemaJson);
      }

      if (schemaJson.containsKey('oneOf')) {
        final result = _parseUnion(name, schemaJson, isAnyOf: false);
        if (!_schemas.containsKey(name)) {
          _schemas[name] = result;
        }
        return result;
      }

      if (schemaJson.containsKey('anyOf')) {
        final result = _parseUnion(name, schemaJson, isAnyOf: true);
        if (!_schemas.containsKey(name)) {
          _schemas[name] = result;
        }
        return result;
      }

      if (schemaJson.containsKey('allOf')) {
        final result = _parseAllOf(name, schemaJson);
        if (!_schemas.containsKey(name)) {
          _schemas[name] = result;
        }
        return result;
      }

      if (type == 'object' || schemaJson.containsKey('properties') || schemaJson.containsKey('additionalProperties')) {
        final result = _parseObject(name, schemaJson);
        if (!_schemas.containsKey(name)) {
          _schemas[name] = result;
        }
        return result;
      }

      if (type == 'array') {
        return _parseArray(name, schemaJson);
      }

      return _parsePrimitive(schemaJson);
    } finally {
      _resolving.remove(name);
    }
  }

  void _collectInlineSchemas(List<IrOperation> operations) {
    for (final op in operations) {
      _collectSchemaFromBody(op.requestBody);
      for (final resp in op.responses) {
        for (final mt in resp.content.values) {
          _registerInlineSchema(mt.schema);
        }
      }
      for (final param in op.parameters) {
        _registerInlineSchema(param.schema);
      }
    }
  }

  void _collectSchemaFromBody(IrRequestBody? body) {
    if (body == null) return;
    for (final mt in body.content.values) {
      _registerInlineSchema(mt.schema);
    }
  }

  void _registerInlineSchema(IrSchema? schema) {
    if (schema == null) return;
    if (schema is IrObjectSchema && !_schemas.containsKey(schema.name)) {
      _schemas[schema.name] = schema;
    } else if (schema is IrEnumSchema && !_schemas.containsKey(schema.name)) {
      _schemas[schema.name] = schema;
    } else if (schema is IrUnionSchema && !_schemas.containsKey(schema.name)) {
      _schemas[schema.name] = schema;
    } else if (schema is IrListSchema) {
      _registerInlineSchema(schema.items);
    } else if (schema is IrMapSchema) {
      _registerInlineSchema(schema.values);
    }
  }

  IrEnumSchema _parseEnum(String name, Map<String, dynamic> schemaJson) {
    final values = <IrEnumValue>[];
    final enumList = getList(schemaJson, 'enum') ?? [];
    final type = getString(schemaJson, 'type') ?? 'string';

    for (final value in enumList) {
      final strVal = value.toString();
      final dartName = _toEnumName(strVal);
      values.add(IrEnumValue(name: dartName, jsonValue: strVal));
    }

    return IrEnumSchema(
      name: _toPascalCase(name),
      values: values,
      enumType: type == 'integer' ? IrPrimitiveType.integer : IrPrimitiveType.string,
      description: getString(schemaJson, 'description'),
      isDeprecated: getBool(schemaJson, 'deprecated') ?? false,
    );
  }

  IrSchema _parseUnion(String name, Map<String, dynamic> schemaJson, {required bool isAnyOf}) {
    final key = isAnyOf ? 'anyOf' : 'oneOf';
    final items = getList(schemaJson, key) ?? [];
    final discriminatorMap = getMap(schemaJson, 'discriminator');
    final discriminatorProp = getString(discriminatorMap ?? {}, 'propertyName');
    final mapping = getMap(discriminatorMap ?? {}, 'mapping') ?? {};
    final isNullable = _isSchemaNullable(schemaJson);

    final variants = <IrUnionVariant>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      if (item.containsKey(r'$ref')) {
        final ref = item[r'$ref'] as String;
        final refName = _refToName(ref);
        final discValue = mapping[ref] ?? mapping[refName] ?? refName;
        variants.add(IrUnionVariant(
          discriminatorValue: mapperToString(discValue),
          schema: IrRefSchema(refName: refName),
        ));
      } else {
        final itemType = getString(item, 'type');
        if (itemType == 'null') continue;
        if (itemType == 'string' && item.containsKey('enum')) {
          final enumSchema = _parseEnum('${name}_${variants.length}', item);
          variants.add(IrUnionVariant(schema: enumSchema));
        } else if (item.containsKey('properties') || itemType == 'object') {
          final objSchema = _parseObject('${name}_${variants.length}', item);
          variants.add(IrUnionVariant(schema: objSchema));
        } else {
          final primitive = _parsePrimitive(item);
          variants.add(IrUnionVariant(schema: primitive));
        }
      }
    }

    return IrUnionSchema(
      name: _toPascalCase(name),
      variants: variants,
      discriminatorProperty: discriminatorProp,
      isAnyOf: isAnyOf,
      isNullable: isNullable,
      description: getString(schemaJson, 'description'),
    );
  }

  IrSchema _parseAllOf(String name, Map<String, dynamic> schemaJson) {
    final items = getList(schemaJson, 'allOf') ?? [];
    final refs = <IrRefSchema>[];
    final inlineObjs = <IrObjectSchema>[];
    final directProps = <IrProperty>[];
    final isNullable = _isSchemaNullable(schemaJson);
    String? discriminatorProp;

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! Map<String, dynamic>) continue;

      if (item.containsKey(r'$ref')) {
        final ref = item[r'$ref'] as String;
        final refName = _refToName(ref);
        refs.add(IrRefSchema(refName: refName));
      } else if (item.containsKey('properties') || item.containsKey('type') && item['type'] == 'object') {
        final obj = _parseObject('${name}_inline_$i', item);
        inlineObjs.add(obj);
      } else if (item.containsKey('discriminator')) {
        discriminatorProp = getString(getMap(item, 'discriminator') ?? {}, 'propertyName');
      }
    }

    if (schemaJson.containsKey('properties')) {
      final props = getMap(schemaJson, 'properties') ?? {};
      final required = List<String>.from(getList(schemaJson, 'required') ?? []);
      for (final entry in props.entries) {
        if (entry.value is! Map<String, dynamic>) continue;
        final propSchema = _parseSchema('${name}_${entry.key}', entry.value as Map<String, dynamic>);
        directProps.add(IrProperty(
          name: entry.key,
          jsonKey: _toCamelCase(entry.key) != entry.key ? entry.key : null,
          schema: propSchema,
          isRequired: required.contains(entry.key),
          isNullable: _isSchemaNullable(entry.value as Map<String, dynamic>? ?? {}),
          description: getString(entry.value as Map<String, dynamic>, 'description'),
        ));
      }
    }

    return IrObjectSchema(
      name: _toPascalCase(name),
      properties: directProps,
      allOfRefs: refs,
      allOfInline: inlineObjs,
      discriminatorProperty: discriminatorProp,
      isNullable: isNullable,
      description: getString(schemaJson, 'description'),
    );
  }

  void _resolveAllOfRefs(IrObjectSchema schema) {
    for (final ref in schema.allOfRefs) {
      final resolved = _schemas[ref.refName];
      if (resolved is IrObjectSchema) {
        _resolveAllOfRefs(resolved);
      }
    }
  }

  IrObjectSchema _parseObject(String name, Map<String, dynamic> schemaJson) {
    final props = <IrProperty>[];
    final propsMap = getMap(schemaJson, 'properties') ?? {};
    final required = List<String>.from(getList(schemaJson, 'required') ?? []);
    final isNullable = _isSchemaNullable(schemaJson);

    for (final entry in propsMap.entries) {
      if (entry.value is! Map<String, dynamic>) continue;
      final propJson = entry.value as Map<String, dynamic>;
      final propSchema = _parseSchema('${name}_${entry.key}', propJson);
      props.add(IrProperty(
        name: entry.key,
        jsonKey: _toCamelCase(entry.key) != entry.key ? entry.key : null,
        schema: propSchema,
        isRequired: required.contains(entry.key),
        isNullable: _isSchemaNullable(propJson),
        isReadOnly: getBool(propJson, 'readOnly') ?? false,
        isWriteOnly: getBool(propJson, 'writeOnly') ?? false,
        description: getString(propJson, 'description'),
        defaultValue: propJson['default'],
      ));
    }

    IrSchema? additionalProps;
    if (schemaJson.containsKey('additionalProperties')) {
      final ap = schemaJson['additionalProperties'];
      if (ap is Map<String, dynamic>) {
        additionalProps = _parseSchema('${name}_additional', ap);
      }
    }

    String? discProp;
    final discMap = getMap(schemaJson, 'discriminator');
    if (discMap != null) {
      discProp = getString(discMap, 'propertyName');
    }

    return IrObjectSchema(
      name: _toPascalCase(name),
      properties: props,
      additionalProperties: additionalProps,
      discriminatorProperty: discProp,
      requiredFields: required.isEmpty ? null : required,
      isNullable: isNullable,
      description: getString(schemaJson, 'description'),
      isDeprecated: getBool(schemaJson, 'deprecated') ?? false,
    );
  }

  IrSchema _parseArray(String name, Map<String, dynamic> schemaJson) {
    final items = schemaJson['items'];
    final isNullable = _isSchemaNullable(schemaJson);

    if (items is Map<String, dynamic>) {
      final itemSchema = _parseSchema('${name}_item', items);
      return IrListSchema(items: itemSchema, isNullable: isNullable);
    }

    return IrListSchema(
      items: IrPrimitiveSchema(type: IrPrimitiveType.any),
      isNullable: isNullable,
    );
  }

  IrPrimitiveSchema _parsePrimitive(Map<String, dynamic> schemaJson) {
    final type = getString(schemaJson, 'type') ?? 'object';
    final format = getString(schemaJson, 'format');
    final isNullable = _isSchemaNullable(schemaJson);

    final irType = switch (type) {
      'string' => switch (format) {
        'date-time' => IrPrimitiveType.dateTime,
        'date' => IrPrimitiveType.date,
        'uri' || 'url' => IrPrimitiveType.uri,
        'binary' => IrPrimitiveType.binary,
        'byte' => IrPrimitiveType.base64,
        _ => IrPrimitiveType.string,
      },
      'integer' => IrPrimitiveType.integer,
      'number' => IrPrimitiveType.number,
      'boolean' => IrPrimitiveType.boolean,
      'object' => IrPrimitiveType.any,
      'array' => IrPrimitiveType.any,
      _ => IrPrimitiveType.any,
    };

    return IrPrimitiveSchema(
      type: irType,
      format: format,
      pattern: getString(schemaJson, 'pattern'),
      minimum: getDouble(schemaJson, 'minimum'),
      maximum: getDouble(schemaJson, 'maximum'),
      minLength: getInt(schemaJson, 'minLength'),
      maxLength: getInt(schemaJson, 'maxLength'),
      minItems: getInt(schemaJson, 'minItems'),
      maxItems: getInt(schemaJson, 'maxItems'),
      isNullable: isNullable,
      defaultValue: schemaJson['default'],
      description: getString(schemaJson, 'description'),
      isDeprecated: getBool(schemaJson, 'deprecated') ?? false,
    );
  }

  List<IrOperation> _parseOperations() {
    final operations = <IrOperation>[];
    final paths = getMapOrEmpty(_doc, 'paths');

    for (final pathEntry in paths.entries) {
      final path = pathEntry.key;
      final pathItem = pathEntry.value;
      if (pathItem is! Map<String, dynamic>) continue;

      final pathParams = <Map<String, dynamic>>[];
      final pathParamList = getList(pathItem, 'parameters') ?? [];
      for (final p in pathParamList) {
        if (p is Map<String, dynamic>) pathParams.add(p);
      }

      for (final method in ['get', 'post', 'put', 'delete', 'patch', 'options', 'head']) {
        final operation = pathItem[method];
        if (operation is! Map<String, dynamic>) continue;

        operations.add(_parseOperation(path, method, operation, pathParams));
      }
    }

    return operations;
  }

  IrOperation _parseOperation(String path, String method, Map<String, dynamic> op, List<Map<String, dynamic>> pathParams) {
    final params = <IrParameter>[];
    final allParams = <Map<String, dynamic>>[...pathParams];

    final opParams = getList(op, 'parameters') ?? [];
    for (final p in opParams) {
      if (p is Map<String, dynamic>) allParams.add(p);
    }

    for (final p in allParams) {
      final pRef = p.containsKey(r'$ref') ? _resolveRef(p[r'$ref'] as String) : p;
      if (pRef == null) continue;

      final loc = switch (getString(pRef, 'in') ?? 'query') {
        'path' => IrParameterLocation.path,
        'query' => IrParameterLocation.query,
        'header' => IrParameterLocation.header,
        'cookie' => IrParameterLocation.cookie,
        _ => IrParameterLocation.query,
      };

      params.add(IrParameter(
        name: getString(pRef, 'name') ?? '',
        location: loc,
        schema: _parseSchema(getString(pRef, 'name') ?? 'param', pRef.containsKey('schema') ? (pRef['schema'] as Map<String, dynamic>? ?? {}) : pRef),
        isRequired: getBool(pRef, 'required') ?? (loc == IrParameterLocation.path),
        description: getString(pRef, 'description'),
        style: _parseStyle(getString(pRef, 'style')),
        explode: getBool(pRef, 'explode') ?? true,
      ));
    }

    IrRequestBody? requestBody;
    final rb = op['requestBody'];
    if (rb is Map<String, dynamic>) {
      final rbResolved = rb.containsKey(r'$ref') ? _resolveRef(rb[r'$ref'] as String) : rb;
      if (rbResolved != null) {
        final opName = getString(op, 'operationId') ??
            '${method}_${path.replaceAll(RegExp(r'[{}]'), '').replaceAll('/', '_').replaceAll('-', '_')}';
        requestBody = _parseRequestBody(rbResolved, _toPascalCase(opName));
      }
    }

    final responses = <IrResponse>[];
    final responsesMap = getMapOrEmpty(op, 'responses');
    for (final entry in responsesMap.entries) {
      final statusCode = entry.key;
      final respValue = entry.value;
      if (respValue is! Map<String, dynamic>) continue;

      final respResolved = respValue.containsKey(r'$ref') ? _resolveRef(respValue[r'$ref'] as String) : respValue;
      if (respResolved == null) continue;

      final contentMap = getMapOrEmpty(respResolved, 'content');
      final content = <String, IrMediaType>{};
      for (final ce in contentMap.entries) {
        if (ce.value is! Map<String, dynamic>) continue;
        final schemaJson = (ce.value as Map<String, dynamic>)['schema'];
        IrSchema? schema;
        if (schemaJson is Map<String, dynamic>) {
          schema = _parseSchema('${method}_${statusCode}_response', schemaJson);
        }
        content[ce.key] = IrMediaType(contentType: ce.key, schema: schema);
      }

      final headers = <IrResponseHeader>[];
      final headersMap = getMapOrEmpty(respResolved, 'headers');
      for (final he in headersMap.entries) {
        if (he.value is! Map<String, dynamic>) continue;
        final hSchema = (he.value as Map<String, dynamic>)['schema'];
        if (hSchema is Map<String, dynamic>) {
          headers.add(IrResponseHeader(
            name: he.key,
            schema: _parseSchema('header_${he.key}', hSchema),
            isRequired: getBool(he.value as Map<String, dynamic>, 'required') ?? false,
            description: getString(he.value as Map<String, dynamic>, 'description'),
          ));
        }
      }

      responses.add(IrResponse(
        statusCode: statusCode,
        description: getString(respResolved, 'description'),
        content: content,
        headers: headers,
      ));
    }

    final operationId = getString(op, 'operationId') ?? '${method}_${path.replaceAll(RegExp(r'[{}]'), '').replaceAll('/', '_').replaceAll('-', '_')}';

    final tags = (getList(op, 'tags') ?? []).map((t) => t.toString()).toList();

    return IrOperation(
      operationId: _toCamelCase(operationId),
      httpMethod: method.toUpperCase(),
      path: path,
      summary: getString(op, 'summary'),
      description: getString(op, 'description'),
      parameters: params,
      requestBody: requestBody,
      responses: responses,
      tags: tags,
      isDeprecated: getBool(op, 'deprecated') ?? false,
      security: _parseSecurity(op),
    );
  }

  IrRequestBody _parseRequestBody(Map<String, dynamic> rb, String operationName) {
    final content = <String, IrMediaType>{};
    final contentMap = getMapOrEmpty(rb, 'content');
    for (final entry in contentMap.entries) {
      if (entry.value is! Map<String, dynamic>) continue;
      final schemaJson = (entry.value as Map<String, dynamic>)['schema'];
      IrSchema? schema;
      if (schemaJson is Map<String, dynamic>) {
        schema = _parseSchema('${operationName}_body_${entry.key.replaceAll('/', '_')}', schemaJson);
      }
      content[entry.key] = IrMediaType(contentType: entry.key, schema: schema);
    }
    return IrRequestBody(
      content: content,
      isRequired: getBool(rb, 'required') ?? false,
      description: getString(rb, 'description'),
    );
  }

  List<IrServer> _parseServers() {
    final servers = <IrServer>[];
    final serverList = getList(_doc, 'servers') ?? [];
    for (final s in serverList) {
      if (s is! Map<String, dynamic>) continue;
      final vars = <String, IrServerVariable>{};
      final varsMap = getMapOrEmpty(s, 'variables');
      for (final ve in varsMap.entries) {
        if (ve.value is! Map<String, dynamic>) continue;
        final vv = ve.value as Map<String, dynamic>;
        vars[ve.key] = IrServerVariable(
          defaultValue: getString(vv, 'default') ?? '',
          enumValues: getList(vv, 'enum')?.map((e) => e.toString()).toList(),
          description: getString(vv, 'description'),
        );
      }
      servers.add(IrServer(
        url: getString(s, 'url') ?? '',
        description: getString(s, 'description'),
        variables: vars,
      ));
    }
    return servers;
  }

  Map<String, IrSecurityScheme> _parseSecuritySchemes() {
    final schemes = <String, IrSecurityScheme>{};
    final secMap = getMapOrEmpty(_components, 'securitySchemes');
    for (final entry in secMap.entries) {
      if (entry.value is! Map<String, dynamic>) continue;
      final sv = entry.value as Map<String, dynamic>;
      schemes[entry.key] = IrSecurityScheme(
        name: entry.key,
        type: getString(sv, 'type') ?? '',
        scheme: getString(sv, 'scheme'),
        bearerFormat: getString(sv, 'bearerFormat'),
        description: getString(sv, 'description'),
      );
    }
    return schemes;
  }

  List<Map<String, List<String>>> _parseSecurity(Map<String, dynamic> op) {
    final sec = getList(op, 'security') ?? [];
    return sec.whereType<Map<String, dynamic>>().map((m) {
      final result = <String, List<String>>{};
      for (final entry in m.entries) {
        result[entry.key] = (entry.value as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      }
      return result;
    }).toList();
  }

  Map<String, dynamic>? _resolveRef(String ref) {
    final parts = ref.replaceFirst('#/', '').split('/');
    if (parts.isEmpty) return null;
    dynamic current = _doc;
    for (final part in parts) {
      if (current is Map<String, dynamic>) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current is Map<String, dynamic> ? current : null;
  }

  String _refToName(String ref) {
    final parts = ref.split('/');
    return _toPascalCase(parts.last);
  }

  static bool _isSchemaNullable(Map<String, dynamic> schemaJson) {
    if (schemaJson.containsKey('nullable') && schemaJson['nullable'] == true) return true;
    if (schemaJson.containsKey('oneOf')) {
      final items = schemaJson['oneOf'] as List<dynamic>?;
      if (items != null) {
        for (final item in items) {
          if (item is Map<String, dynamic> && item['type'] == 'null') return true;
        }
      }
    }
    if (schemaJson.containsKey('anyOf')) {
      final items = schemaJson['anyOf'] as List<dynamic>?;
      if (items != null) {
        for (final item in items) {
          if (item is Map<String, dynamic> && item['type'] == 'null') return true;
        }
      }
    }
    return false;
  }

  IrEncodingStyle? _parseStyle(String? style) {
    return switch (style) {
      'simple' => IrEncodingStyle.simple,
      'label' => IrEncodingStyle.label,
      'matrix' => IrEncodingStyle.matrix,
      'form' => IrEncodingStyle.form,
      'spaceDelimited' => IrEncodingStyle.spaceDelimited,
      'pipeDelimited' => IrEncodingStyle.pipeDelimited,
      'deepObject' => IrEncodingStyle.deepObject,
      _ => null,
    };
  }

  static String _toPascalCase(String s) {
    if (s.isEmpty) return s;
    return s.split(RegExp(r'[_\-\s]+')).map((part) {
      if (part.isEmpty) return '';
      return part[0].toUpperCase() + part.substring(1);
    }).join();
  }

  static String _toCamelCase(String s) {
    if (s.isEmpty) return s;
    final p = _toPascalCase(s);
    return p[0].toLowerCase() + p.substring(1);
  }

  static String _toEnumName(String value) {
    if (value.isEmpty) return 'empty';
    var name = value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').replaceAll(RegExp(r'_+'), '_');
    if (RegExp(r'^[0-9]').hasMatch(name)) name = 'value_$name';
    if (name.startsWith('_')) name = name.substring(1);
    if (name.endsWith('_')) name = name.substring(0, name.length - 1);
    return name;
  }

  static Map<String, dynamic> getMapOrEmpty(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  static String mapperToString(dynamic v) {
    if (v is String) return v;
    if (v is Map) return v.keys.first.toString();
    return v.toString();
  }
}
