// Conditional export: on native platforms (iOS/Android/desktop) the dart:io
// implementation is used; on web the browser download implementation is used.
export 'file_saver_web.dart'
    if (dart.library.io) 'file_saver_native.dart';
