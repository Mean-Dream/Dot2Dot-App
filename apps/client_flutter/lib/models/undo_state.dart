import 'package:flutter/painting.dart';
import 'dot_model.dart';

class ProjectState {
  final List<Dot> dots;
  final List<Offset> erasedPoints;

  ProjectState({required this.dots, required this.erasedPoints});
}
