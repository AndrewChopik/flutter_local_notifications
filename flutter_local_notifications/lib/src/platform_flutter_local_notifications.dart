import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:timezone/timezone.dart';

import 'helpers.dart';
import 'platform_specifics/android/initialization_settings.dart';
import 'platform_specifics/android/method_channel_mappers.dart';
import 'platform_specifics/android/notification_channel.dart';
import 'platform_specifics/android/notification_details.dart';
import 'platform_specifics/ios/initialization_settings.dart';
import 'platform_specifics/ios/method_channel_mappers.dart';
import 'platform_specifics/ios/notification_details.dart';
import 'typedefs.dart';
import 'types.dart';
import 'type_mappers.dart';
import 'tz_datetime_mapper.dart';

const MethodChannel _channel =
    MethodChannel('dexterous.com/flutter/local_notifications');

/// An implementation of a local notifications platform using method channels.
class MethodChannelFlutterLocalNotificationsPlugin
    extends FlutterLocalNotificationsPlatform {
  @override
  Future<void> cancel(int id) {
    validateId(id);
    return _channel.invokeMethod('cancel', id);
  }

  @override
  Future<void> cancelAll() {
    return _channel.invokeMethod('cancelAll');
  }

  @override
  Future<NotificationAppLaunchDetails> getNotificationAppLaunchDetails() async {
    final result =
        await _channel.invokeMethod('getNotificationAppLaunchDetails');
    return NotificationAppLaunchDetails(result['notificationLaunchedApp'],
        result.containsKey('payload') ? result['payload'] : null);
  }

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async {
    final List<Map<dynamic, dynamic>> pendingNotifications =
        await _channel.invokeListMethod('pendingNotificationRequests');
    return pendingNotifications
        .map((pendingNotification) => PendingNotificationRequest(
            pendingNotification['id'],
            pendingNotification['title'],
            pendingNotification['body'],
            pendingNotification['payload']))
        .toList();
  }
}

/// Android implementation of the local notifications plugin.
class AndroidFlutterLocalNotificationsPlugin
    extends MethodChannelFlutterLocalNotificationsPlugin {
  SelectNotificationCallback _onSelectNotification;

  /// Initializes the plugin. Call this method on application before using the plugin further.
  /// This should only be done once. When a notification created by this plugin was used to launch the app,
  /// calling `initialize` is what will trigger to the `onSelectNotification` callback to be fire.
  Future<bool> initialize(AndroidInitializationSettings initializationSettings,
      {SelectNotificationCallback onSelectNotification}) async {
    _onSelectNotification = onSelectNotification;
    _channel.setMethodCallHandler(_handleMethod);
    return await _channel.invokeMethod(
        'initialize', initializationSettings.toMap());
  }

  /// Schedules a notification to be shown at the specified time.
  ///
  /// The [androidAllowWhileIdle] parameter determines if the notification should still be shown at the exact time
  /// when the device is in a low-power idle mode.
  @Deprecated(
      'Deprecated due to problems with timezones, particularly when it comes to daylight savings. Use zonedSchedule instead.')
  Future<void> schedule(int id, String title, String body,
      DateTime scheduledDate, AndroidNotificationDetails notificationDetails,
      {String payload, bool androidAllowWhileIdle = false}) async {
    validateId(id);
    var serializedPlatformSpecifics =
        notificationDetails?.toMap() ?? Map<String, Object>();
    serializedPlatformSpecifics['allowWhileIdle'] = androidAllowWhileIdle;
    await _channel.invokeMethod('schedule', <String, Object>{
      'id': id,
      'title': title,
      'body': body,
      'millisecondsSinceEpoch': scheduledDate.millisecondsSinceEpoch,
      'platformSpecifics': serializedPlatformSpecifics,
      'payload': payload ?? ''
    });
  }

  /// Schedules a notification to be shown at the specified time relative to a specific timezone.
  Future<void> zonedSchedule(int id, String title, String body,
      TZDateTime scheduledDate, AndroidNotificationDetails notificationDetails,
      {String payload,
      ScheduledNotificationRepeatFrequency
          scheduledNotificationRepeatFrequency}) async {
    validateId(id);
    //assert(scheduledDate.isAfter(DateTime.now()));

    var serializedPlatformSpecifics =
        notificationDetails?.toMap() ?? Map<String, Object>();

    await _channel.invokeMethod(
        'zonedSchedule',
        <String, Object>{
          'id': id,
          'title': title,
          'body': body,
          'platformSpecifics': serializedPlatformSpecifics,
          'payload': payload ?? ''
        }
          ..addAll(scheduledDate.toMap())
          ..addAll(scheduledNotificationRepeatFrequency == null
              ? {}
              : {
                  'scheduledNotificationRepeatFrequency':
                      scheduledNotificationRepeatFrequency.index
                }));
  }

  /// Shows a notification on a daily interval at the specified time.
  @Deprecated(
      'Deprecated due to problems with timezones, particularly when it comes to daylight savings. Use zonedSchedule instead.')
  Future<void> showDailyAtTime(int id, String title, String body,
      Time notificationTime, AndroidNotificationDetails notificationDetails,
      {String payload}) async {
    validateId(id);
    await _channel.invokeMethod('showDailyAtTime', <String, Object>{
      'id': id,
      'title': title,
      'body': body,
      'calledAt': DateTime.now().millisecondsSinceEpoch,
      'repeatInterval': RepeatInterval.Daily.index,
      'repeatTime': notificationTime.toMap(),
      'platformSpecifics': notificationDetails?.toMap(),
      'payload': payload ?? ''
    });
  }

  /// Shows a notification on weekly interval at the specified day and time.
  @Deprecated(
      'Deprecated due to problems with timezones, particularly when it comes to daylight savings. Use zonedSchedule instead.')
  Future<void> showWeeklyAtDayAndTime(
      int id,
      String title,
      String body,
      Day day,
      Time notificationTime,
      AndroidNotificationDetails notificationDetails,
      {String payload}) async {
    validateId(id);

    await _channel.invokeMethod('showWeeklyAtDayAndTime', <String, Object>{
      'id': id,
      'title': title,
      'body': body,
      'calledAt': DateTime.now().millisecondsSinceEpoch,
      'repeatInterval': RepeatInterval.Weekly.index,
      'repeatTime': notificationTime.toMap(),
      'day': day.value,
      'platformSpecifics': notificationDetails?.toMap(),
      'payload': payload ?? ''
    });
  }

  @override
  Future<void> show(int id, String title, String body,
      {AndroidNotificationDetails notificationDetails, String payload}) {
    validateId(id);
    return _channel.invokeMethod(
      'show',
      <String, Object>{
        'id': id,
        'title': title,
        'body': body,
        'payload': payload ?? '',
        'platformSpecifics': notificationDetails?.toMap(),
      },
    );
  }

  @override
  Future<void> periodicallyShow(
      int id, String title, String body, RepeatInterval repeatInterval,
      {AndroidNotificationDetails notificationDetails,
      String payload,
      bool androidAllowWhileIdle = false}) async {
    validateId(id);
    var serializedPlatformSpecifics =
        notificationDetails?.toMap() ?? Map<String, Object>();
    serializedPlatformSpecifics['allowWhileIdle'] = androidAllowWhileIdle;
    await _channel.invokeMethod('periodicallyShow', <String, Object>{
      'id': id,
      'title': title,
      'body': body,
      'calledAt': DateTime.now().millisecondsSinceEpoch,
      'repeatInterval': repeatInterval.index,
      'platformSpecifics': serializedPlatformSpecifics,
      'payload': payload ?? '',
    });
  }

  /// Creates a notification channel.
  ///
  /// Only applies to Android 8.0+.
  Future<void> createNotificationChannel(
      AndroidNotificationChannel notificationChannel) {
    return _channel.invokeMethod(
        'createNotificationChannel', notificationChannel.toMap());
  }

  Future<void> deleteNotificationChannel(String channelId) {
    return _channel.invokeMethod('deleteNotificationChannel', channelId);
  }

  Future<void> _handleMethod(MethodCall call) {
    switch (call.method) {
      case 'selectNotification':
        return _onSelectNotification(call.arguments);
      default:
        return Future.error('Method not defined');
    }
  }
}

/// iOS implementation of the local notifications plugin.
class IOSFlutterLocalNotificationsPlugin
    extends MethodChannelFlutterLocalNotificationsPlugin {
  SelectNotificationCallback _onSelectNotification;

  DidReceiveLocalNotificationCallback _onDidReceiveLocalNotification;

  /// Initializes the plugin.
  ///
  /// Call this method on application before using the plugin further.
  /// This should only be done once. When a notification created by this plugin was used to launch the app,
  /// calling `initialize` is what will trigger to the `onSelectNotification` callback to be fire.
  ///
  /// Initialisation may also request notification permissions where users will see a permissions prompt. This may be fine
  /// in cases where it's acceptable to do this when the application runs for the first time. However, if your application
  /// needs to do this at a later point in time, set the [IOSInitializationSettings.requestAlertPermission],
  /// [IOSInitializationSettings.requestBadgePermission] and [IOSInitializationSettings.requestSoundPermission] values to false.
  /// [requestPermissions] can then be called to request permissions when needed.
  Future<bool> initialize(IOSInitializationSettings initializationSettings,
      {SelectNotificationCallback onSelectNotification}) async {
    _onSelectNotification = onSelectNotification;
    _onDidReceiveLocalNotification =
        initializationSettings.onDidReceiveLocalNotification;
    _channel.setMethodCallHandler(_handleMethod);
    return await _channel.invokeMethod(
        'initialize', initializationSettings.toMap());
  }

  /// Requests the specified permission(s) from user and returns current permission status.
  Future<bool> requestPermissions({bool sound, bool alert, bool badge}) {
    return _channel.invokeMethod('requestPermissions', {
      'sound': sound,
      'alert': alert,
      'badge': badge,
    });
  }

  /// Schedules a notification to be shown at the specified time with an optional payload that is passed through when a notification is tapped.
  @Deprecated(
      'Deprecated due to problems with timezones, particularly when it comes to daylight savings. Use zonedSchedule instead.')
  Future<void> schedule(int id, String title, String body,
      DateTime scheduledDate, IOSNotificationDetails notificationDetails,
      {String payload}) async {
    validateId(id);
    await _channel.invokeMethod('schedule', <String, Object>{
      'id': id,
      'title': title,
      'body': body,
      'millisecondsSinceEpoch': scheduledDate.millisecondsSinceEpoch,
      'platformSpecifics': notificationDetails?.toMap(),
      'payload': payload ?? ''
    });
  }

  /// Schedules a notification to be shown at the specified time relative to a specific timezone.
  Future<void> zonedSchedule(int id, String title, String body,
      TZDateTime scheduledDate, IOSNotificationDetails notificationDetails,
      {String payload,
      ScheduledNotificationRepeatFrequency
          scheduledNotificationRepeatFrequency}) async {
    validateId(id);
    assert(scheduledDate.isAfter(DateTime.now()));
    var serializedPlatformSpecifics =
        notificationDetails?.toMap() ?? Map<String, Object>();
    await _channel.invokeMethod(
        'zonedSchedule',
        <String, Object>{
          'id': id,
          'title': title,
          'body': body,
          'platformSpecifics': serializedPlatformSpecifics,
          'payload': payload ?? '',
        }
          ..addAll(scheduledDate.toMap())
          ..addAll(scheduledNotificationRepeatFrequency == null
              ? {}
              : {
                  'scheduledNotificationRepeatFrequency':
                      scheduledNotificationRepeatFrequency.index
                }));
  }

  /// Shows a notification on a daily interval at the specified time.
  @Deprecated(
      'Deprecated due to problems with timezones, particularly when it comes to daylight savings. Use zonedSchedule instead.')
  Future<void> showDailyAtTime(int id, String title, String body,
      Time notificationTime, IOSNotificationDetails notificationDetails,
      {String payload}) async {
    validateId(id);
    await _channel.invokeMethod('showDailyAtTime', <String, Object>{
      'id': id,
      'title': title,
      'body': body,
      'calledAt': DateTime.now().millisecondsSinceEpoch,
      'repeatInterval': RepeatInterval.Daily.index,
      'repeatTime': notificationTime.toMap(),
      'platformSpecifics': notificationDetails?.toMap(),
      'payload': payload ?? ''
    });
  }

  /// Shows a notification on weekly interval at the specified day and time.
  @Deprecated(
      'Deprecated due to problems with timezones, particularly when it comes to daylight savings. Use zonedSchedule instead.')
  Future<void> showWeeklyAtDayAndTime(
      int id,
      String title,
      String body,
      Day day,
      Time notificationTime,
      IOSNotificationDetails notificationDetails,
      {String payload}) async {
    validateId(id);

    await _channel.invokeMethod('showWeeklyAtDayAndTime', <String, Object>{
      'id': id,
      'title': title,
      'body': body,
      'calledAt': DateTime.now().millisecondsSinceEpoch,
      'repeatInterval': RepeatInterval.Weekly.index,
      'repeatTime': notificationTime.toMap(),
      'day': day.value,
      'platformSpecifics': notificationDetails?.toMap(),
      'payload': payload ?? ''
    });
  }

  @override
  Future<void> show(int id, String title, String body,
      {IOSNotificationDetails notificationDetails, String payload}) {
    validateId(id);
    return _channel.invokeMethod(
      'show',
      <String, Object>{
        'id': id,
        'title': title,
        'body': body,
        'payload': payload ?? '',
        'platformSpecifics': notificationDetails?.toMap(),
      },
    );
  }

  @override
  Future<void> periodicallyShow(
      int id, String title, String body, RepeatInterval repeatInterval,
      {IOSNotificationDetails notificationDetails, String payload}) async {
    validateId(id);
    await _channel.invokeMethod('periodicallyShow', <String, Object>{
      'id': id,
      'title': title,
      'body': body,
      'calledAt': DateTime.now().millisecondsSinceEpoch,
      'repeatInterval': repeatInterval.index,
      'platformSpecifics': notificationDetails?.toMap(),
      'payload': payload ?? ''
    });
  }

  Future<void> _handleMethod(MethodCall call) {
    switch (call.method) {
      case 'selectNotification':
        return _onSelectNotification(call.arguments);

      case 'didReceiveLocalNotification':
        return _onDidReceiveLocalNotification(
            call.arguments['id'],
            call.arguments['title'],
            call.arguments['body'],
            call.arguments['payload']);
      default:
        return Future.error('Method not defined');
    }
  }
}
