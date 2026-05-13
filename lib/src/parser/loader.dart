import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';

Future<Map<String, dynamic>> loadSpec(String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    throw Exception('Spec file not found: $path');
  }
  final content = await file.readAsString();
  if (path.endsWith('.yaml') || path.endsWith('.yml')) {
    final doc = loadYaml(content);
    return _yamlToJson(doc);
  }
  return json.decode(content) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> loadSpecFromUrl(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final content = await response.transform(utf8.decoder).join();
    if (url.endsWith('.yaml') || url.endsWith('.yml')) {
      final doc = loadYaml(content);
      return _yamlToJson(doc);
    }
    return json.decode(content) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

dynamic _yamlToJson(dynamic yamlValue) {
  if (yamlValue is YamlMap) {
    final map = <String, dynamic>{};
    for (final entry in yamlValue.entries) {
      map[entry.key.toString()] = _yamlToJson(entry.value);
    }
    return map;
  }
  if (yamlValue is YamlList) {
    return yamlValue.map(_yamlToJson).toList();
  }
  return yamlValue;
}

String? getString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null) return null;
  return value.toString();
}

bool? getBool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is bool) return value;
  return null;
}

int? getInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is double) return value.toInt();
  return null;
}

double? getDouble(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is num) return value.toDouble();
  return null;
}

List<dynamic>? getList(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is List) return value;
  return null;
}

Map<String, dynamic>? getMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}
