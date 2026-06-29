import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;

import '../ir/ir.dart';
import 'dart/model_generator.dart';
import 'dart/api_generator.dart';
import 'dart/support_generator.dart';

/// Generates Dart code from an [IrApiDocument].

/// Produces models, API services, result types, and support files
/// (auth interceptors, pagination, etc.) into [outputDir].
///
/// Supports parallel file writing via [Isolate.spawn] when [useIsolates]
/// is `true` (default), and `--use-compute` wrappers via [useCompute].
class CodeGenerator {
  final IrApiDocument doc;
  final String outputDir;
  final String packageName;
  final bool useIsolates;
  final bool useCompute;

  CodeGenerator({
    required this.doc,
    required this.outputDir,
    required this.packageName,
    this.useIsolates = true,
    this.useCompute = false,
  });

  Future<void> generate() async {
    final outputPath = p.join(outputDir, packageName);
    await Directory(p.join(outputPath, 'lib', 'src', 'models'))
        .create(recursive: true);
    await Directory(p.join(outputPath, 'lib', 'src', 'api'))
        .create(recursive: true);
    await Directory(p.join(outputPath, 'lib', 'src', 'core'))
        .create(recursive: true);

    final files = _collectAllFiles();

    if (useIsolates && files.length > 10) {
      await _writeWithIsolates(files, outputPath);
    } else {
      for (final file in files) {
        await _writeFile(p.join(outputPath, file.path), file.content);
      }
    }

    print('Generated ${files.length} files in $outputPath');
    await _formatOutput(outputPath);
  }

  Future<void> _formatOutput(String outputPath) async {
    try {
      final result = await Process.run(
        'dart',
        ['format', '.'],
        workingDirectory: outputPath,
      );
      if (result.exitCode != 0) {
        print('Warning: dart format exited with code ${result.exitCode}');
      } else {
        print('Formatted generated code.');
      }
    } catch (e) {
      print('Warning: Could not format generated code: $e');
    }
  }

  List<GeneratedFile> _collectAllFiles() {
    final files = <GeneratedFile>[];

    for (final entry in doc.schemas.entries) {
      try {
        files.add(ModelGenerator.generate(entry.value,
            packageName: packageName, schemaName: entry.key));
      } catch (e) {
        print('Warning: Failed to generate model for ${entry.key}: $e');
      }
    }

    if (doc.operationsByTag.isNotEmpty) {
      files.addAll(ApiGenerator.generateServices(
        doc.operationsByTag,
        packageName: packageName,
        servers: doc.servers,
        useCompute: useCompute,
      ));

      files.add(ApiGenerator.generateRootClient(
        doc.operationsByTag,
        packageName: packageName,
        servers: doc.servers,
        securitySchemes: doc.securitySchemes,
        useCompute: useCompute,
      ));
    }

    files.addAll(SupportFilesGenerator.generateAll(
      packageName: packageName,
      info: doc.info,
      servers: doc.servers,
      securitySchemes: doc.securitySchemes,
      schemas: doc.schemas,
      operationsByTag: doc.operationsByTag,
    ));

    return files;
  }

  Future<void> _writeWithIsolates(
      List<GeneratedFile> files, String basePath) async {
    final chunkSize = 8;
    final futures = <Future>[];

    for (var i = 0; i < files.length; i += chunkSize) {
      final chunk = files.skip(i).take(chunkSize).toList();
      futures.add(_writeChunk(chunk, basePath));
    }

    await Future.wait(futures);
  }

  Future<void> _writeChunk(List<GeneratedFile> files, String basePath) async {
    final receivePort = ReceivePort();
    final isolateFiles = files
        .map((f) => {
              'path': p.join(basePath, f.path),
              'content': f.content,
            })
        .toList();

    await Isolate.spawn(_writeIsolate, [receivePort.sendPort, isolateFiles]);

    await receivePort.first;
    receivePort.close();
  }

  static void _writeIsolate(List<dynamic> args) {
    final sendPort = args[0] as SendPort;
    final files = args[1] as List<Map<String, String>>;

    for (final file in files) {
      final filePath = file['path']!;
      final content = file['content']!;
      final dir = Directory(p.dirname(filePath));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(filePath).writeAsStringSync(content);
    }

    Isolate.exit(sendPort, true);
  }

  Future<void> _writeFile(String path, String content) async {
    final file = File(path);
    await file.create(recursive: true);
    await file.writeAsString(content);
  }
}
