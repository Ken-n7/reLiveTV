import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'player.dart';
import 'settings.dart';

/// App-specific native calls (Android: MainActivity.kt). No plugins needed.
const platform = MethodChannel('relivetv/platform');

/// True while Android shows the video in its floating picture-in-picture window.
final inPip = ValueNotifier(false);

bool _pausedByApp = false;

/// What happens when the viewer leaves the app while something plays:
/// background play off → pause (battery, data), resume on return;
/// on → keep playing (Android: picture-in-picture or a notification service).
void initPlatform() {
  AppLifecycleListener(onHide: _onHide, onShow: _onShow); // registers itself with the app binding
  if (!Platform.isAndroid) return;
  platform.setMethodCallHandler(_fromAndroid);
  void syncPip() => platform.invokeMethod('setPipAllowed', backgroundPlay.value && playback.channel != null && playback.status == PlayStatus.playing);
  playback.addListener(syncPip);
  backgroundPlay.addListener(syncPip);
}

void _onHide() {
  if (playback.channel == null || inPip.value) return;
  final playing = playback.player.state.playing;
  if (backgroundPlay.value) {
    if (Platform.isAndroid && playing) platform.invokeMethod('startPlaybackService', {'title': playback.channel!.name, 'playing': true});
    return;
  }
  if (playing) {
    _pausedByApp = true;
    playback.suspend(true);
    playback.player.pause();
  }
}

void _onShow() {
  if (Platform.isAndroid) platform.invokeMethod('stopPlaybackService');
  if (_pausedByApp) {
    _pausedByApp = false;
    playback.suspend(false);
    playback.player.play();
  }
}

Future<void> _fromAndroid(MethodCall call) async {
  switch (call.method) {
    case 'notificationAction' when call.arguments == 'toggle':
      await playback.player.playOrPause();
      final channel = playback.channel;
      if (channel != null) await platform.invokeMethod('startPlaybackService', {'title': channel.name, 'playing': playback.player.state.playing});
    case 'notificationAction' when call.arguments == 'stop':
      playback.close();
    case 'pipChanged':
      inPip.value = call.arguments as bool;
    case 'pipClosed': // floating window dismissed: stop playing, like YouTube
      await platform.invokeMethod('stopPlaybackService');
      await playback.player.pause();
  }
}

/// Android 13+ asks before showing the background-play notification.
Future<void> requestNotificationPermission() async {
  if (Platform.isAndroid) await platform.invokeMethod('requestNotifications');
}
