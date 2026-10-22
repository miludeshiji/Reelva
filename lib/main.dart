import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reelva/app/app.dart';
import 'package:reelva/core/errors/error_handling.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandling();
  runApp(const ProviderScope(child: ReelvaApp()));
}
