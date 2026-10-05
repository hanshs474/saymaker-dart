import 'dart:io';

import 'package:saymaker/saymaker.dart';

Future<void> main() async {
  final client = SayMaker(Platform.environment['SAYMAKER_API_KEY'] ?? '');
  try {
    print(await client.generate('a paper-cut layered mountain range at dusk'));
  } on SayMakerException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  } finally {
    client.close();
  }
}
