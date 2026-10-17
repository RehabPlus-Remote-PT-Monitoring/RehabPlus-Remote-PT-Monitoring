import 'package:flutter/material.dart';

/// Global keys so services (e.g. push notifications) can navigate or show a
/// SnackBar without a BuildContext.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();
