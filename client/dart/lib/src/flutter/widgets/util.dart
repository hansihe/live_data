import 'package:flutter/widgets.dart';

EdgeInsets buildEdgeInsertsGeometry(dynamic data) {
  var left = 0.0;
  var top = 0.0;
  var right = 0.0;
  var bottom = 0.0;

  if (data is double) {
    left = data;
    top = data;
    right = data;
    bottom = data;
  } else {
    var all = data["all"] as double?;
    if (all != null) {
      left = all;
      top = all;
      right = all;
      bottom = all;
    }

    var vertical = data["vertical"] as double?;
    if (vertical != null) {
      top = vertical;
      bottom = vertical;
    }

    var horizontal = data["horizontal"] as double?;
    if (horizontal != null) {
      left = horizontal;
      right = horizontal;
    }

    var leftN = data["left"] as double?;
    if (leftN != null) left = leftN;

    var topN = data["top"] as double?;
    if (topN != null) top = topN;

    var rightN = data["right"] as double?;
    if (rightN != null) right = rightN;

    var bottomN = data["bottom"] as double?;
    if (bottomN != null) bottom = bottomN;
  }

  return EdgeInsets.only(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
  );
}

TextStyle buildTextStyle(dynamic data) {
  if (data == null) return TextStyle();

  return TextStyle(
    fontFamily: data["font_family"] as String,
    fontSize: data["font_size"] as double,
    fontWeight: doIf(data["font_weight"], (d) => FontWeight.values[(d as int).clamp(0, 8)]),
  );
}

R? doIf<T, R>(T? data, R mapper(T)) {
  if (data != null) return mapper(data);
}
