import 'dart:async';

import 'package:phoenix_socket/phoenix_socket.dart';
import 'package:async/async.dart';

//import './diff_render.dart';
import './encoding/json.dart';

class LiveDataSocket {

  bool connected = false;
  late Stream connectedStream;

  late PhoenixSocket socket;

  int idCounter = 0;

  LiveDataSocket(String endpoint) {
    socket = PhoenixSocket(endpoint);

    connectedStream = StreamGroup.merge([
      socket.closeStream.map((_) => false),
      socket.openStream.map((_) => true)
    ]).asBroadcastStream();

    connectedStream.listen((state) {
      connected = state;
    });

    socket.connect();
  }

  LiveData liveData(String route, dynamic params) {
    String topic = "dv:c:$idCounter";
    idCounter += 1;

    return LiveData(this, topic, route, params);
  }

}

class LiveData {
  final LiveDataSocket socket;

  final String _topic;
  final String _route;
  final dynamic _params;

  late final PhoenixChannel _channel;

  JSONEncoding _encoding = JSONEncoding();

  late final Stream dataStream;
  dynamic get data {
    return _encoding.out;
  }

  LiveData(this.socket, this._topic, this._route, this._params) {
    _channel = socket.socket.addChannel(topic: _topic, parameters: {
      "r": [_route, _params]
    });

    var controller = StreamController();
    dataStream = controller.stream;

    _channel.messages.listen((event) {
      if (event.event.value == "o") {
        if (_encoding.handleMessage(event.payload!["o"]!)) {
          controller.add(_encoding.out);
        }
      } else {
        throw "unhandled event ${event.event.value}";
      }
    });

    _channel.join();
  }

  pushEvent(dynamic data) {
    _channel.push("e", {"d": data});
  }

}
