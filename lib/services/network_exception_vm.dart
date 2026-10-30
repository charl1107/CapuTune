/// VM/mobile variant: the real dart:io socket exception type, referenced
/// through the conditional import so `download_service.dart` keeps compiling
/// on web (where dart:io does not exist).
library;

import 'dart:io';

typedef NetworkSocketException = SocketException;
