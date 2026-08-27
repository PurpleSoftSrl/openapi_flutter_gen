import 'model_generator.dart';
import 'naming.dart';
import '../../ir/ir.dart';

class SupportFilesGenerator {
  static List<GeneratedFile> generateAll({
    required String packageName,
    required IrApiInfo info,
    required List<IrServer> servers,
    required Map<String, IrSecurityScheme> securitySchemes,
    required Map<String, IrSchema> schemas,
    required Map<String, List<IrOperation>> operationsByTag,
  }) {
    return [
      _generatePubspec(packageName, info),
      _generateAnalysisOptions(),
      _generateBarrelFile(packageName,
          schemas: schemas, operationsByTag: operationsByTag),
      _generateInterceptorHelpers(),
      _generatePaginationHelpers(),
      _generateAuth(securitySchemes),
      _generateErrorHandler(),
    ];
  }

  static GeneratedFile _generateErrorHandler() {
    final content = '''
${generateFileHeader()}

import 'package:dio/dio.dart';

typedef StatusCodeCallback = void Function(Response<dynamic> response);
typedef AnyStatusCodeCallback = void Function(int statusCode, Response<dynamic> response);

class ApiErrorInterceptor extends Interceptor {
  ApiErrorInterceptor({
    this.onBadRequest,
    this.onUnauthorized,
    this.onForbidden,
    this.onNotFound,
    this.onConflict,
    this.onTooManyRequests,
    this.onServerError,
    this.onAny,
    this.skipGlobal = false,
  });

  final StatusCodeCallback? onBadRequest;
  final StatusCodeCallback? onUnauthorized;
  final StatusCodeCallback? onForbidden;
  final StatusCodeCallback? onNotFound;
  final StatusCodeCallback? onConflict;
  final StatusCodeCallback? onTooManyRequests;
  final StatusCodeCallback? onServerError;
  final AnyStatusCodeCallback? onAny;
  final bool skipGlobal;

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final status = response.statusCode ?? 0;
    final perCall = response.requestOptions.extra['perCallErrorHandler'];
    if (perCall is ApiErrorInterceptor) {
      perCall._dispatch(status, response);
      if (perCall.skipGlobal) {
        handler.next(response);
        return;
      }
    }
    _dispatch(status, response);
    handler.next(response);
  }

  void _dispatch(int status, Response<dynamic> response) {
    onAny?.call(status, response);
    switch (status) {
      case 400: onBadRequest?.call(response);
      case 401: onUnauthorized?.call(response);
      case 403: onForbidden?.call(response);
      case 404: onNotFound?.call(response);
      case 409: onConflict?.call(response);
      case 429: onTooManyRequests?.call(response);
      default:
        if (status >= 500) onServerError?.call(response);
    }
  }
}
''';
    return GeneratedFile(
        path: 'lib/src/core/error_handler.dart', content: content);
  }

  static GeneratedFile _generateAuth(Map<String, IrSecurityScheme> schemes) {
    if (schemes.isEmpty)
      return GeneratedFile(
          path: 'lib/src/core/auth.dart',
          content: '// No security schemes defined\n');

    final buf = StringBuffer(generateFileHeader());
    buf.writeln('import \'package:dio/dio.dart\';');
    buf.writeln();

    for (final entry in schemes.entries) {
      final name = entry.key;
      final scheme = entry.value;
      final className = '${sanitizeClassName(name)}Security';

      switch (scheme.type) {
        case 'http':
          final httpScheme = (scheme.scheme ?? 'bearer').toLowerCase();
          final prefix = httpScheme == 'bearer' ? 'Bearer ' : '';
          final headerName = 'Authorization';

          buf.writeln('class $className {');
          buf.writeln(
              '  $className({this.token, this.tokenProvider, this.headerName = \'$headerName\', this.tokenPrefix = \'$prefix\'});');
          buf.writeln();
          buf.writeln('  final String? token;');
          buf.writeln('  final Future<String> Function()? tokenProvider;');
          buf.writeln('  final String headerName;');
          buf.writeln('  final String tokenPrefix;');
          buf.writeln();
          buf.writeln(
              '  Interceptor createInterceptor() => _${className}Interceptor(this);');
          buf.writeln('}');
          buf.writeln();
          buf.writeln('class _${className}Interceptor extends Interceptor {');
          buf.writeln('  _${className}Interceptor(this.security);');
          buf.writeln('  final $className security;');
          buf.writeln();
          buf.writeln('  @override');
          buf.writeln(
              '  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {');
          buf.writeln('    var token = security.token;');
          buf.writeln('    token ??= await security.tokenProvider?.call();');
          buf.writeln('    if (token != null && token.isNotEmpty) {');
          buf.writeln(
              '      options.headers[security.headerName] = \'\${security.tokenPrefix}\$token\';');
          buf.writeln('    }');
          buf.writeln('    handler.next(options);');
          buf.writeln('  }');
          buf.writeln('}');
          buf.writeln();
          break;

        case 'apiKey':
          final paramName = scheme.name;
          buf.writeln('enum ${className}Location { header, query, cookie }');
          buf.writeln();
          buf.writeln('class $className {');
          buf.writeln(
              '  $className({required this.apiKey, this.keyName = \'$paramName\', this.location = ${className}Location.header});');
          buf.writeln();
          buf.writeln('  final String apiKey;');
          buf.writeln('  final String keyName;');
          buf.writeln('  final ${className}Location location;');
          buf.writeln();
          buf.writeln(
              '  Interceptor createInterceptor() => _${className}Interceptor(this);');
          buf.writeln('}');
          buf.writeln();
          buf.writeln('class _${className}Interceptor extends Interceptor {');
          buf.writeln('  _${className}Interceptor(this.security);');
          buf.writeln('  final $className security;');
          buf.writeln();
          buf.writeln('  @override');
          buf.writeln(
              '  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {');
          buf.writeln('    switch (security.location) {');
          buf.writeln('      case ${className}Location.header:');
          buf.writeln(
              '        options.headers[security.keyName] = security.apiKey;');
          buf.writeln('      case ${className}Location.query:');
          buf.writeln(
              '        options.queryParameters[security.keyName] = security.apiKey;');
          buf.writeln('      case ${className}Location.cookie:');
          buf.writeln(
              '        options.headers[\'Cookie\'] = \'\${security.keyName}=\${security.apiKey}\';');
          buf.writeln('    }');
          buf.writeln('    handler.next(options);');
          buf.writeln('  }');
          buf.writeln('}');
          buf.writeln();
          break;

        case 'oauth2':
        case 'openIdConnect':
          buf.writeln('class $className {');
          buf.writeln(
              '  $className({this.accessToken, this.tokenProvider, this.scopes = const {}});');
          buf.writeln();
          buf.writeln('  final String? accessToken;');
          buf.writeln(
              '  final Future<String> Function(Iterable<String> scopes)? tokenProvider;');
          buf.writeln('  final Set<String> scopes;');
          buf.writeln();
          buf.writeln(
              '  Interceptor createInterceptor() => _${className}Interceptor(this);');
          buf.writeln('}');
          buf.writeln();
          buf.writeln('class _${className}Interceptor extends Interceptor {');
          buf.writeln('  _${className}Interceptor(this.security);');
          buf.writeln('  final $className security;');
          buf.writeln();
          buf.writeln('  @override');
          buf.writeln(
              '  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {');
          buf.writeln('    var token = security.accessToken;');
          buf.writeln(
              '    token ??= await security.tokenProvider?.call(security.scopes);');
          buf.writeln('    if (token != null && token.isNotEmpty) {');
          buf.writeln(
              '      options.headers[\'Authorization\'] = \'Bearer \$token\';');
          buf.writeln('    }');
          buf.writeln('    handler.next(options);');
          buf.writeln('  }');
          buf.writeln('}');
          buf.writeln();
          break;

        default:
          buf.writeln('class $className {');
          buf.writeln(
              '  Interceptor createInterceptor() => _NoopInterceptor();');
          buf.writeln('}');
          buf.writeln();
          break;
      }
    }

    return GeneratedFile(
        path: 'lib/src/core/auth.dart', content: buf.toString());
  }

  static GeneratedFile _generatePubspec(String packageName, IrApiInfo info) {
    return GeneratedFile(
      path: 'pubspec.yaml',
      content: generatePubspecContent(packageName,
          info.description ?? 'Generated API client for ${info.title}'),
    );
  }

  static GeneratedFile _generateAnalysisOptions() {
    return GeneratedFile(
      path: 'analysis_options.yaml',
      content: '''
include: package:lints/recommended.yaml

linter:
  rules:
    - always_declare_return_types
    - prefer_const_constructors
    - prefer_const_declarations
    - avoid_print
''',
    );
  }

  static GeneratedFile _generateBarrelFile(
    String packageName, {
    required Map<String, IrSchema> schemas,
    required Map<String, List<IrOperation>> operationsByTag,
  }) {
    final buf = StringBuffer(generateFileHeader());
    buf.writeln();

    buf.writeln('export \'src/api/api_client.dart\';');
    buf.writeln();
    buf.writeln('export \'src/core/interceptors.dart\';');
    buf.writeln('export \'src/core/pagination.dart\';');
    buf.writeln('export \'src/core/auth.dart\';');
    buf.writeln('export \'src/core/error_handler.dart\';');

    final modelExports = <String>[];
    final seenModels = <String>{};
    for (final name in schemas.keys) {
      final fileName = sanitizeClassName(name).toLowerCase();
      if (seenModels.add(fileName)) {
        modelExports.add('export \'src/models/$fileName.dart\';');
      }
    }
    if (modelExports.isNotEmpty) {
      buf.writeln();
      modelExports.sort();
      buf.writeln(modelExports.join('\n'));
    }

    final resultExports = <String>[];
    final serviceExports = <String>[];
    final seenResults = <String>{};
    for (final tag in operationsByTag.keys.toList()..sort()) {
      final tagFileName = sanitizeClassName(tag).toLowerCase();
      serviceExports.add('export \'src/api/${tagFileName}_api.dart\';');

      for (final op in operationsByTag[tag]!) {
        final cleanName =
            sanitizeFieldName(op.operationId).replaceAll(RegExp(r'_+$'), '');
        final resultFileName = '${cleanName}_result'.toLowerCase();
        if (seenResults.add(resultFileName)) {
          resultExports.add('export \'src/api/$resultFileName.dart\';');
        }
      }
    }
    if (serviceExports.isNotEmpty) {
      buf.writeln();
      buf.writeln(serviceExports.join('\n'));
    }
    if (resultExports.isNotEmpty) {
      buf.writeln();
      resultExports.sort();
      buf.writeln(resultExports.join('\n'));
    }

    return GeneratedFile(
      path: 'lib/$packageName.dart',
      content: buf.toString(),
    );
  }

  static GeneratedFile _generateInterceptorHelpers() {
    final content = '''
${generateFileHeader()}

import 'package:dio/dio.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    this.token,
    this.tokenProvider,
    this.headerName = 'Authorization',
    this.tokenPrefix = 'Bearer ',
  });

  final String? token;
  final Future<String> Function()? tokenProvider;
  final String headerName;
  final String tokenPrefix;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _addAuth(options);
    handler.next(options);
  }

  void _addAuth(RequestOptions options) {
    final t = token;
    if (t != null && t.isNotEmpty) {
      options.headers[headerName] = '\$tokenPrefix\$t';
    }
  }
}

class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
    this.retryableStatuses = const {408, 429, 500, 502, 503, 504},
  });

  final int maxRetries;
  final Duration retryDelay;
  final Set<int> retryableStatuses;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final requestOptions = err.requestOptions;
    final retryCount = requestOptions.extra['retry_count'] as int? ?? 0;

    if (retryCount < maxRetries &&
        (err.response?.statusCode != null &&
            retryableStatuses.contains(err.response!.statusCode!))) {
      await Future<void>.delayed(retryDelay * (retryCount + 1));

      requestOptions.extra['retry_count'] = retryCount + 1;

      try {
        final response = await Dio().fetch<dynamic>(requestOptions);
        handler.resolve(response);
      } catch (e) {
        handler.next(DioException(requestOptions: requestOptions, error: e));
      }
    } else {
      handler.next(err);
    }
  }
}

class LoggingInterceptor extends Interceptor {
  final void Function(String message) logger;

  LoggingInterceptor({void Function(String)? logger})
      : logger = logger ?? _noop;

  static void _noop(String message) {}

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    logger('\${options.method} \${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    logger('\${response.statusCode} \${response.requestOptions.path}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    logger('ERROR \${err.message}');
    handler.next(err);
  }
}
''';

    return GeneratedFile(
        path: 'lib/src/core/interceptors.dart', content: content);
  }

  static GeneratedFile _generatePaginationHelpers() {
    final content = '''
${generateFileHeader()}

abstract class PaginatedResponse<T> {
  List<T> get items;
  Future<PaginatedResponse<T>?> getNextPage();
  bool hasNextPage();
}

class OffsetPaginatedResponse<T> extends PaginatedResponse<T> {
  OffsetPaginatedResponse({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
    this.fetchNext,
  });

  @override
  final List<T> items;
  final int total;
  final int offset;
  final int limit;
  final Future<OffsetPaginatedResponse<T>?> Function(int nextOffset)? fetchNext;

  @override
  Future<OffsetPaginatedResponse<T>?> getNextPage() {
    final nextOffset = offset + limit;
    if (nextOffset >= total) return Future.value(null);
    if (fetchNext == null) return Future.value(null);
    return fetchNext!(nextOffset);
  }

  @override
  bool hasNextPage() => offset + limit < total;
}

class CursorPaginatedResponse<T, C> extends PaginatedResponse<T> {
  CursorPaginatedResponse({
    required this.items,
    this.nextCursor,
    this.fetchNext,
  });

  @override
  final List<T> items;
  final C? nextCursor;
  final Future<CursorPaginatedResponse<T, C>?> Function(C cursor)? fetchNext;

  @override
  Future<CursorPaginatedResponse<T, C>?> getNextPage() {
    if (nextCursor == null) return Future.value(null);
    if (fetchNext == null) return Future.value(null);
    return fetchNext!(nextCursor as C);
  }

  @override
  bool hasNextPage() => nextCursor != null;
}

extension PaginationExtension<T> on Future<PaginatedResponse<T>> {
  Future<void> forEach(Future<void> Function(T item) callback) async {
    PaginatedResponse<T>? current = await this;
    while (current != null) {
      for (final item in current.items) {
        await callback(item);
      }
      if (!current.hasNextPage()) break;
      current = await current.getNextPage();
    }
  }

  Future<List<T>> toList() async {
    final result = <T>[];
    await forEach((item) async => result.add(item));
    return result;
  }
}
''';

    return GeneratedFile(
        path: 'lib/src/core/pagination.dart', content: content);
  }
}
