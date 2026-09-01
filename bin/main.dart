import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:openapi_flutter_gen/src/cli/runner.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('spec',
        abbr: 's',
        help: 'Path to the OpenAPI spec file (JSON or YAML)',
        mandatory: false)
    ..addOption('spec-url', abbr: 'u', help: 'URL to the OpenAPI spec file')
    ..addOption('output',
        abbr: 'o',
        help: 'Output directory for generated code',
        defaultsTo: './generated')
    ..addOption('package-name',
        abbr: 'p',
        help: 'Dart package name for generated code',
        defaultsTo: 'api_client')
    ..addFlag('no-isolates',
        help: 'Disable isolate-based parallel generation', defaultsTo: false)
    ..addFlag('use-compute',
        help: 'Generate Isolate.run wrappers for heavy JSON deserialization',
        defaultsTo: false)
    ..addFlag('pure-surface',
        help: 'Emit transport-neutral clients over an injected RequestAdapter '
            '(pure-surface / Kiota-lite mode) instead of self-contained dio.',
        defaultsTo: false)
    ..addOption('core-package',
        help: 'Package name for the shared pure-surface runtime.',
        defaultsTo: 'purple_openapi_core')
    ..addOption('emit-target',
        allowed: ['client', 'runtime'],
        help: 'client = generate a client from a spec (default); '
            'runtime = emit the purple_openapi_core runtime package.',
        defaultsTo: 'client')
    ..addFlag('help', abbr: 'h', help: 'Show usage', negatable: false);

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      print('openapi_flutter_gen - OpenAPI to Dart/Flutter code generator');
      print('');
      print('Usage: dart run openapi_flutter_gen [options]');
      print('');
      print(parser.usage);
      return;
    }

    final specPath = results['spec'] as String?;
    final specUrl = results['spec-url'] as String?;
    final emitTarget = results['emit-target'] as String;

    if (emitTarget == 'client' && specPath == null && specUrl == null) {
      stderr.writeln('Error: Either --spec or --spec-url is required');
      print('');
      print(parser.usage);
      exit(1);
    }

    final runner = Runner();
    await runner.run(
      specPath: specPath ?? '',
      specUrl: specUrl,
      outputDir: p.absolute(results['output'] as String),
      packageName: results['package-name'] as String,
      useIsolates: !(results['no-isolates'] as bool),
      useCompute: results['use-compute'] as bool,
      pureSurface: results['pure-surface'] as bool,
      corePackage: results['core-package'] as String,
      emitTarget: emitTarget,
    );
  } on ArgParserException catch (e) {
    stderr.writeln('Error: ${e.message}');
    print('');
    print(parser.usage);
    exit(1);
  } catch (e, stack) {
    stderr.writeln('Error: $e');
    if (arguments.contains('--verbose')) {
      stderr.writeln(stack);
    }
    exit(1);
  }
}
