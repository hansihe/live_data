import 'dart:async';
import 'dart:developer';

import 'package:live_data_client/live_data_client.dart';

import 'package:flutter/widgets.dart';
import 'package:phoenix_socket/phoenix_socket.dart';
import 'package:async/async.dart';

class DataViewSocket extends InheritedWidget {
  final DataViewSocketService service;

  DataViewSocket({Key? key, required this.service, required Widget child}) : super(key: key, child: child);

  @override
  bool updateShouldNotify(covariant DataViewSocket old) {
    if (service != old.service) {
      throw Exception('Services must be constant!');
    }

    return false;
  }
}

class DataViewSocketService {
  late LiveDataSocket socket;

  DataViewSocketService(String endpoint) {
    socket = LiveDataSocket(endpoint);
  }

  LiveData open(String route, dynamic params) {
    return socket.liveData(route, params);
  }

  static DataViewSocketService of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DataViewSocket>()!.service;
  }
}
