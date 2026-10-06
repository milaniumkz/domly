class AppEnv {
  static const String backendBaseUrl = String.fromEnvironment(
    'DOMLY_BACKEND_BASE_URL',
    defaultValue: 'https://domly.kz/api/v1',
  );

  static const String firebaseProjectId = 'domly-d0f91';

  static const String firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '288330515337',
  );
  static const String firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: 'domly-d0f91.firebasestorage.app',
  );
  static const String firebaseAuthDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
    defaultValue: 'domly-d0f91.firebaseapp.com',
  );
  static const String firebaseApiKeyAndroid = String.fromEnvironment(
    'FIREBASE_API_KEY_ANDROID',
    defaultValue: 'AIzaSyAzPWe_eZjvjRlJ3BvqT2c9y0L6nSQSIw8',
  );
  static const String firebaseApiKeyIos = String.fromEnvironment(
    'FIREBASE_API_KEY_IOS',
    defaultValue: 'AIzaSyBfPsaosWxvTemHUPgUbF2R0BaleNcrvHs',
  );
  static const String firebaseApiKeyWeb = String.fromEnvironment(
    'FIREBASE_API_KEY_WEB',
    defaultValue: 'AIzaSyATusQAZ4b14N8aUUPREx7AUU5X0dmbLw4',
  );
  static const String mapsApiKey = String.fromEnvironment(
    'MAPS_API_KEY',
    defaultValue: '',
  );
  static const String firebaseAppIdAndroidCustomer = String.fromEnvironment(
    'FIREBASE_APP_ID_ANDROID_CUSTOMER',
    defaultValue: '1:288330515337:android:272dcba306b05783cd9758',
  );
  static const String firebaseAppIdAndroidPro = String.fromEnvironment(
    'FIREBASE_APP_ID_ANDROID_PRO',
    defaultValue: '1:288330515337:android:e34939ba65c8e796cd9758',
  );
  static const String firebaseAppIdIosCustomer = String.fromEnvironment(
    'FIREBASE_APP_ID_IOS_CUSTOMER',
    defaultValue: '1:288330515337:ios:3ec0c30b9a9cabcccd9758',
  );
  static const String firebaseAppIdIosPro = String.fromEnvironment(
    'FIREBASE_APP_ID_IOS_PRO',
    defaultValue: '1:288330515337:ios:b0586c947c0a8c8ecd9758',
  );
  static const String firebaseAppIdWeb = String.fromEnvironment(
    'FIREBASE_APP_ID_WEB',
    defaultValue: '1:288330515337:web:d894db4a58831b07cd9758',
  );
  static const String firebaseMessagingVapidKey = String.fromEnvironment(
    'FIREBASE_MESSAGING_VAPID_KEY',
    defaultValue: '',
  );


  static const String customerUserId = String.fromEnvironment(
    'CUSTOMER_USER_ID',
    defaultValue: 'customer_demo',
  );
  static const String cleanerUserId = String.fromEnvironment(
    'CLEANER_USER_ID',
    defaultValue: 'cleaner_demo',
  );

  static const bool seedFirestoreOnStart = bool.fromEnvironment(
    'SEED_FIRESTORE_ON_START',
    defaultValue: false,
  );
}
