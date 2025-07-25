import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tatar_shower/models/auth_request.dart';
import 'package:tatar_shower/models/complete_schower_request.dart';
import 'package:tatar_shower/models/delete_schedule_request.dart';
import 'package:tatar_shower/models/message_response.dart';
import 'package:tatar_shower/models/update_schedule_request.dart';
import 'package:tatar_shower/models/push_token_request.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'package:tatar_shower/models/streak_response.dart';
import 'package:tatar_shower/models/tips_response.dart';
import 'dart:developer' as developer;
import 'package:tatar_shower/models/register_request.dart';

import '../models/schedule.dart';

class ApiService {
  static const String _baseUrl_1 = "http://10.0.2.2:8001/api";
  static const String _baseUrl_2 = "http://10.0.2.2:8002/api";
  static const String _baseUrl_3 = "http://10.0.2.2:8003/api";
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<String> getRandomTip() async {
    try {
      final tipsResponse = await getTips();
      if (tipsResponse.tips.isEmpty) {
        return "list empty";
      }

      // Get random tip from the list
      final random = Random();
      final randomIndex = random.nextInt(tipsResponse.tips.length);
      return tipsResponse.tips[randomIndex];
    } catch (e) {
      return "load error";
    }
  }

  Future<TipsResponse> getTips() async {
    final url = Uri.parse("$_baseUrl_3/tips");
    final headers = {"Content-Type": "application/json"};

    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> respJson = jsonDecode(response.body);
      return TipsResponse.fromJson(respJson);
    } else {
      throw Exception(
        "Failed to load tips: ${response.statusCode} ${response.body}",
      );
    }
  }

  Future<StreakResponse> getStreak() async {
    final url = Uri.parse("$_baseUrl_3/streak");
    String? token = await _secureStorage.read(key: "jwtToken");
    final headers = {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };

    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final Map<String, dynamic> respJson = jsonDecode(response.body);
      return StreakResponse.fromJson(respJson);
    } else {
      throw Exception(
        "Failed to load streak: ${response.statusCode} ${response.body}",
      );
    }
  }

  Future<MessageResponse> registerPushToken() async {
    try {
      developer.log(
        'Starting push token registration',
        name: 'PushNotifications',
      );

      // Get FCM token
      String? fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken == null || fcmToken.isEmpty) {
        throw Exception("Failed to get FCM token");
      }

      // Determine platform
      String platform = Platform.isAndroid ? 'android' : 'ios';
      developer.log('Platform: $platform', name: 'PushNotifications');

      // Create request
      final request = PushTokenRequest(token: fcmToken, platform: platform);

      // Send to server
      final url = Uri.parse("$_baseUrl_1/user/push-token");
      String? token = await _secureStorage.read(key: "jwtToken");
      final headers = {
        "Content-Type": "application/json",
        if (token != null) "Authorization": "Bearer $token",
      };
      final body = jsonEncode(request.toJson());
      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        final Map<String, dynamic> respJson = jsonDecode(response.body);
        developer.log(
          'Push token registered successfully',
          name: 'PushNotifications',
        );
        return MessageResponse.fromJson(respJson);
      } else {
        throw Exception(
          "Failed to register push token: ${response.statusCode} ${response.body}",
        );
      }
    } catch (e) {
      developer.log(
        'Error registering push token: $e',
        name: 'PushNotifications',
        error: e,
      );
      throw Exception("Error registering push token: $e");
    }
  }

  Future<void> initializePushNotifications() async {
    try {
      developer.log(
        'Starting push notifications initialization',
        name: 'PushNotifications',
      );

      // Request permission for notifications
      NotificationSettings settings = await FirebaseMessaging.instance
          .requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          );

      developer.log(
        'Permission status: ${settings.authorizationStatus}',
        name: 'PushNotifications',
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        developer.log(
          'User granted permission for notifications',
          name: 'PushNotifications',
        );

        // Get FCM token with retry logic
        String? token = await _getTokenWithRetry();

        if (token != null) {
          developer.log(
            'FCM token received: ${token.substring(0, 20)}...',
            name: 'PushNotifications',
          );

          // Register push token with server
          await registerPushToken();

          // Setup message handlers
          _setupMessageHandlers();

          developer.log(
            'Push notifications initialized successfully',
            name: 'PushNotifications',
          );
        } else {
          throw Exception('Failed to get FCM token after retries');
        }
      } else {
        developer.log(
          'User declined or has not accepted permission for notifications. Status: ${settings.authorizationStatus}',
          name: 'PushNotifications',
          level: 900,
        );
      }
    } catch (e) {
      developer.log(
        'Error initializing push notifications',
        name: 'PushNotifications',
        error: e,
        level: 1000,
      );
      rethrow; // Re-throw to handle in calling code
    }
  }

  // Add this method to your ApiService class
  Future<String?> _getTokenWithRetry({int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        developer.log(
          'Attempting to get FCM token (attempt $attempt)',
          name: 'PushNotifications',
        );

        String? token = await FirebaseMessaging.instance.getToken();

        if (token != null && token.isNotEmpty) {
          return token;
        }

        developer.log(
          'Token is null or empty, retrying...',
          name: 'PushNotifications',
        );
      } catch (e) {
        developer.log(
          'Failed to get token on attempt $attempt: $e',
          name: 'PushNotifications',
          error: e,
        );

        // If this is the last attempt, throw the error
        if (attempt == maxRetries) {
          throw Exception(
            'Failed to get FCM token after $maxRetries attempts: $e',
          );
        }
      }

      // Wait before retrying with exponential backoff
      await Future.delayed(Duration(seconds: attempt * 2));
    }

    return null;
  }

  // Add this method to your ApiService class
  void _setupMessageHandlers() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      developer.log(
        'Received foreground message: ${message.notification?.title}',
        name: 'PushNotifications',
      );
      // Handle foreground notification display here
      // You might want to show a local notification or update UI
    });

    // Handle background message taps
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      developer.log(
        'Message clicked: ${message.notification?.title}',
        name: 'PushNotifications',
      );
      // Handle navigation when user taps notification
      // For example, navigate to schedule screen
    });

    // Listen for token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      developer.log('FCM token refreshed', name: 'PushNotifications');
      // Update token on server when it changes
      registerPushToken().catchError((error) {
        developer.log(
          'Failed to update token after refresh: $error',
          name: 'PushNotifications',
        );
      });
    });
  }

  static void setupForegroundMessageHandler() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      developer.log(
        'Received foreground message: ${message.notification?.title}',
        name: 'PushNotifications',
      );
      // Handle foreground notification display here
      // You might want to show a local notification or update UI
    });
  }

  static void setupBackgroundMessageHandler() {
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      developer.log(
        'Message clicked: ${message.notification?.title}',
        name: 'PushNotifications',
      );
      // Handle navigation when user taps notification
      // For example, navigate to schedule screen
    });
  }

  static Future<void> handleInitialMessage() async {
    RemoteMessage? initialMessage = await FirebaseMessaging.instance
        .getInitialMessage();
    if (initialMessage != null) {
      developer.log(
        'App opened from notification: ${initialMessage.notification?.title}',
        name: 'PushNotifications',
      );
      // TODO Handle navigation for initial message
    } else {
      developer.log('No initial message found', name: 'PushNotifications');
    }
  }

  Future<MessageResponse> registerUser(AuthRequest request) async {
    final url = Uri.parse("$_baseUrl_1/register");
    final headers = {"Content-Type": "application/json"};
    final body = jsonEncode(request.toJson());
    final response = await http.post(url, headers: headers, body: body);

    if (response.statusCode == 200 || response.statusCode == 201) {
      String? authHeader = response.headers['authorization'];
      if (authHeader != null && authHeader.startsWith("Bearer ")) {
        String token = authHeader.substring(7);
        await _secureStorage.write(key: "jwtToken", value: token);
      }
      final Map<String, dynamic> respJson = jsonDecode(response.body);
      return MessageResponse.fromJson(respJson);
    } else {
      throw Exception(
        "Failed to register: ${response.statusCode} ${response.body}",
      );
    }
  }

  Future<MessageResponse> registerUserWithPrefs(RegisterRequest request) async {
    final url = Uri.parse("$_baseUrl_1/register");
    final headers = {"Content-Type": "application/json"};
    final body = jsonEncode(request.toJson());

    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      final authHeader = response.headers['authorization'];
      if (authHeader?.startsWith("Bearer ") == true) {
        await _secureStorage.write(
          key: "jwtToken",
          value: authHeader!.substring(7),
        );
      }
      return MessageResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception(
        "Failed to register: ${response.statusCode} ${response.body}",
      );
    }
  }

  Future<MessageResponse> signInUser(AuthRequest request) async {
    final url = Uri.parse("$_baseUrl_1/signin");
    final headers = {"Content-Type": "application/json"};
    final body = jsonEncode(request.toJson());
    final response = await http.post(url, headers: headers, body: body);

    if (response.statusCode == 200) {
      String? authHeader = response.headers['authorization'];
      if (authHeader != null && authHeader.startsWith("Bearer ")) {
        String token = authHeader.substring(7);
        await _secureStorage.write(key: "jwtToken", value: token);
      }
      final Map<String, dynamic> respJson = jsonDecode(response.body);
      return MessageResponse.fromJson(respJson);
    } else {
      throw Exception(response.body);
    }
  }

  Future<Schedule> getAllSchedules() async {
    final url = Uri.parse("$_baseUrl_2/user/schedules");
    String? token = await _secureStorage.read(key: "jwtToken");
    final headers = {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final Map<String, dynamic> respJson = jsonDecode(response.body);
      return Schedule.fromJson(respJson);
    } else {
      throw Exception(
        "Failed to load schedules: ${response.statusCode} ${response.body}",
      );
    }
  }

  Future<MessageResponse> updateSchedule(UpdateScheduleRequest request) async {
    final url = Uri.parse("$_baseUrl_2/user/schedules");
    String? token = await _secureStorage.read(key: "jwtToken");
    final headers = {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
    final body = jsonEncode(request.toJson());
    final response = await http.put(url, headers: headers, body: body);

    if (response.statusCode == 200) {
      final Map<String, dynamic> respJson = jsonDecode(response.body);
      return MessageResponse.fromJson(respJson);
    } else {
      throw Exception(
        "Failed to update schedule: ${response.statusCode} ${response.body}",
      );
    }
  }

  Future<MessageResponse> deleteSchedule(DeleteScheduleRequest request) async {
    final url = Uri.parse("$_baseUrl_2/user/schedules");
    String? token = await _secureStorage.read(key: "jwtToken");
    final headers = {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
    final body = jsonEncode(request.toJson());
    final http.Request req = http.Request("DELETE", url);
    req.headers.addAll(headers);
    req.body = body;
    final http.StreamedResponse streamedResponse = await req.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final Map<String, dynamic> respJson = jsonDecode(response.body);
      return MessageResponse.fromJson(respJson);
    } else {
      throw Exception(
        "Failed to delete schedule: ${response.statusCode} ${response.body}",
      );
    }
  }

  Future<MessageResponse> completeShower(CompleteShowerRequest request) async {
    final url = Uri.parse("$_baseUrl_2/user/shower/completed");
    String? token = await _secureStorage.read(key: "jwtToken");
    final headers = {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
    final body = jsonEncode(request.toJson());
    final response = await http.post(url, headers: headers, body: body);

    if (response.statusCode == 200) {
      final Map<String, dynamic> respJson = jsonDecode(response.body);
      return MessageResponse.fromJson(respJson);
    } else {
      throw Exception(
        "Failed to complete action: ${response.statusCode} ${response.body}",
      );
    }
  }
}
