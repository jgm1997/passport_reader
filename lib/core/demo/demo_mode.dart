import 'package:flutter/services.dart';

/// True only in the separate demo app (`--flavor demo`). A compile-time
/// constant: in real builds every demo-only branch is removed by the compiler.
const bool kDemoMode = appFlavor == 'demo';
