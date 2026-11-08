import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CompassService {
  static final CompassService instance = CompassService._init();
  CompassService._init();

  static const EventChannel _eventChannel = EventChannel('com.sinyalnol/compass');

  double _currentHeading = 0.0;
  Stream<double>? _headingStream;

  double get currentHeading => _currentHeading;

  Stream<double> get headingStream {
    if (_headingStream != null) return _headingStream!;

    if (!Platform.isAndroid) {
      _headingStream = Stream.value(0.0).asBroadcastStream();
      return _headingStream!;
    }

    _headingStream = _eventChannel
        .receiveBroadcastStream()
        .map((event) {
          final heading = (event as num).toDouble();
          _currentHeading = heading;
          return heading;
        })
        .handleError((error) {
          debugPrint('[CompassService] Sensor error: $error');
          return _currentHeading;
        })
        .asBroadcastStream();

    return _headingStream!;
  }
}
