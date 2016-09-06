import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/java_io.dart';
import 'package:analyzer/src/generated/sdk_io.dart';
import 'package:analyzer/src/generated/source_io.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:analyzer/analyzer.dart';

ArgParser parser = new ArgParser(allowTrailingOptions: true)
  ..addOption('sdk',
      valueHelp: 'path', help: 'Path to the SDK', defaultsTo: currentSdk())
  ..addOption('package-root',
      abbr: 'p', valueHelp: 'path', help: 'Path to the packages folder');

DartSdk dartSdk;
AnalysisContext context;

class SanityCheck extends GeneralizingAstVisitor {
  Source source;
  LineInfo lineInfo;

  SanityCheck(this.source);

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    super.visitVariableDeclarationStatement(node);
    // Skip nodes with explicit type annotations.
    if (node.variables.type != null) return;
    for (var variable in node.variables.variables) {
      var initializer = variable.initializer;
      var type = variable.element.type;
      if (type.isDynamic &&
          initializer != null &&
          !initializer.staticType.isBottom) {
        lineInfo ??= context.computeLineInfo(source);
        var info = lineInfo.getLocation(node.variables.keyword.offset);
        print("$source:$info: ${variable.name} is initialized to "
            "${initializer.staticType} but is dynamic");
      }
    }
  }
}

main(List<String> args) {
  ArgResults options = parser.parse(args);
  context = createContext(options['sdk'], options['package-root'], true);
  for (var lib in dartSdk.sdkLibraries) {
    print('Resolving ${lib.shortName}');
    var uri = Uri.parse(lib.shortName);
    var source = context.sourceFactory.forUri2(uri);
    var element = context.computeLibraryElement(source);
    for (var unit in element.units) {
      var ast = context.resolveCompilationUnit2(unit.source, source);
      ast.accept(new SanityCheck(unit.source));
    }
  }
}

// Returns the path to the current sdk based on `Platform.resolvedExecutable`.
String currentSdk() {
  // The dart executable should be inside dart-sdk/bin/dart.
  return path.dirname(path.dirname(path.absolute(Platform.resolvedExecutable)));
}

AnalysisContext createContext(String sdk, String packageRoot, bool strongMode) {
  if (sdk != null) {
    JavaSystemIO.setProperty("com.google.dart.sdk", sdk);
  }
  dartSdk = DirectoryBasedDartSdk.defaultSdk;

  List<UriResolver> resolvers = [
    new DartUriResolver(dartSdk),
    new ResourceUriResolver(PhysicalResourceProvider.INSTANCE)
  ];

  if (packageRoot != null) {
    var packageDirectory = new JavaFile(packageRoot);
    resolvers.add(new PackageUriResolver([packageDirectory]));
  }

  AnalysisContext context = AnalysisEngine.instance.createAnalysisContext()
    ..sourceFactory = new SourceFactory(resolvers);

  context.analysisOptions = new AnalysisOptionsImpl()
    ..strongMode = strongMode
    ..enableGenericMethods = strongMode;
    // ..preserveComments = false
    // ..hint = false
    // ..generateImplicitErrors = false
    // ..enableSuperMixins = true;

  return context;
}
