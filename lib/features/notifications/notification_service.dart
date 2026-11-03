import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Handles FCM push notifications and local notifications for session updates.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _currentUserId;
  String? _universityId;
  final List<String> _enrolledCourseIds = [];

  /// Initializes FCM and local notifications.
  Future<void> initialize({
    required String userId,
    required String universityId,
    required List<String> enrolledCourseIds,
  }) async {
    if (_isInitialized) return;

    _currentUserId = userId;
    _universityId = universityId;
    _enrolledCourseIds.clear();
    _enrolledCourseIds.addAll(enrolledCourseIds);

    // Request notification permissions
    await _requestPermissions();

    // Initialize local notifications
    await _initLocalNotifications();

    // Get FCM token using new API
    final token = await _messaging.getToken();
    if (token != null) {
      await _saveTokenToFirestore(token);
    }

    // Listen for token refresh using new API
    _messaging.onTokenRefresh.listen(_saveTokenToFirestore);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background messages (app opened from notification)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Handle initial message if app launched from notification
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    _isInitialized = true;
  }

  /// Requests notification permissions for iOS and Android 13+.
  Future<void> _requestPermissions() async {
    // iOS permissions
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // Android 13+ runtime permission - check if permission is granted
    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // Permission granted
    }
  }

  /// Initializes local notifications with platform-specific settings.
  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // Create notification channel for Android
    if (!kIsWeb) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'session_updates',
              'Session Updates',
              description: 'Notifications for attendance session changes',
              importance: Importance.high,
              playSound: true,
            ),
          );
    }
  }

  /// Saves FCM token to Firestore for server-side push notifications.
  Future<void> _saveTokenToFirestore(String token) async {
    if (_currentUserId == null || _universityId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('universities')
          .doc(_universityId)
          .collection('members')
          .doc(_currentUserId)
          .update({
        'fcmToken': token,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Token save failed - log but don't crash
      debugPrint('Failed to save FCM token: $e');
    }
  }

  /// Handles FCM message when app is in foreground.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('Foreground FCM message: ${message.messageId}');

    // Show local notification for foreground messages
    await _showLocalNotification(
      title: message.notification?.title ?? 'Attendance Update',
      body: message.notification?.body ?? '',
      payload: message.data['courseId'],
    );
  }

  /// Handles notification tap (app opened from notification).
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification tapped: ${message.messageId}');
    final courseId = message.data['courseId'];
    if (courseId != null) {
      // Navigation will be handled by the app router/go_router
      // Store the courseId for navigation after app initialization
      _pendingNavigationCourseId = courseId;
    }
  }

  String? _pendingNavigationCourseId;

  /// Returns and clears pending navigation course ID.
  String? consumePendingNavigation() {
    final courseId = _pendingNavigationCourseId;
    _pendingNavigationCourseId = null;
    return courseId;
  }

  /// Handles local notification tap.
  void _onLocalNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      _pendingNavigationCourseId = response.payload;
    }
  }

  /// Shows a local notification.
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'session_updates',
      'Session Updates',
      channelDescription: 'Notifications for attendance session changes',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  /// Updates enrolled courses and re-subscribes to topics.
  Future<void> updateEnrolledCourses(List<String> courseIds) async {
    _enrolledCourseIds.clear();
    _enrolledCourseIds.addAll(courseIds);

    // Subscribe to FCM topics for each course
    for (final courseId in _enrolledCourseIds) {
      await _messaging.subscribeToTopic('course_$courseId');
    }
  }

  /// Shows an in-app session notification (for real-time updates when app is open).
  Future<void> showInAppSessionNotification({
    required String courseName,
    required bool isOpen,
    required String courseId,
  }) async {
    final title = isOpen ? 'Session Started' : 'Session Ended';
    final body = isOpen
        ? 'Attendance session opened for $courseName. Tap to check in.'
        : 'Attendance session ended for $courseName.';

    await _showLocalNotification(
      title: title,
      body: body,
      payload: courseId,
    );
  }

  /// Disposes resources.
  void dispose() {
    _isInitialized = false;
    _currentUserId = null;
    _universityId = null;
    _enrolledCourseIds.clear();
  }
}