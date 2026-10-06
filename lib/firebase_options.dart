import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'app/app_flavor.dart';
import 'app/app_env.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions forFlavor(AppFlavor flavor) {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return flavor == AppFlavor.pro ? androidPro : androidCustomer;
      case TargetPlatform.iOS:
        return flavor == AppFlavor.pro ? iosPro : iosCustomer;
      case TargetPlatform.macOS:
        return flavor == AppFlavor.pro ? iosPro : iosCustomer;
      default:
        return flavor == AppFlavor.pro ? androidPro : androidCustomer;
    }
  }

  static FirebaseOptions get androidCustomer => const FirebaseOptions(
        apiKey: AppEnv.firebaseApiKeyAndroid,
        appId: AppEnv.firebaseAppIdAndroidCustomer,
        messagingSenderId: AppEnv.firebaseMessagingSenderId,
        projectId: AppEnv.firebaseProjectId,
        storageBucket: AppEnv.firebaseStorageBucket,
      );

  static FirebaseOptions get androidPro => const FirebaseOptions(
        apiKey: AppEnv.firebaseApiKeyAndroid,
        appId: AppEnv.firebaseAppIdAndroidPro,
        messagingSenderId: AppEnv.firebaseMessagingSenderId,
        projectId: AppEnv.firebaseProjectId,
        storageBucket: AppEnv.firebaseStorageBucket,
      );

  static FirebaseOptions get iosCustomer => const FirebaseOptions(
        apiKey: AppEnv.firebaseApiKeyIos,
        appId: AppEnv.firebaseAppIdIosCustomer,
        messagingSenderId: AppEnv.firebaseMessagingSenderId,
        projectId: AppEnv.firebaseProjectId,
        storageBucket: AppEnv.firebaseStorageBucket,
        iosBundleId: 'com.domly.customer',
      );

  static FirebaseOptions get iosPro => const FirebaseOptions(
        apiKey: AppEnv.firebaseApiKeyIos,
        appId: AppEnv.firebaseAppIdIosPro,
        messagingSenderId: AppEnv.firebaseMessagingSenderId,
        projectId: AppEnv.firebaseProjectId,
        storageBucket: AppEnv.firebaseStorageBucket,
        iosBundleId: 'com.domly.pro',
      );

  static FirebaseOptions get web => const FirebaseOptions(
        apiKey: AppEnv.firebaseApiKeyWeb,
        appId: AppEnv.firebaseAppIdWeb,
        messagingSenderId: AppEnv.firebaseMessagingSenderId,
        projectId: AppEnv.firebaseProjectId,
        authDomain: AppEnv.firebaseAuthDomain,
        storageBucket: AppEnv.firebaseStorageBucket,
      );
}
