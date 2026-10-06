importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyATusQAZ4b14N8aUUPREx7AUU5X0dmbLw4',
  authDomain: 'domly-d0f91.firebaseapp.com',
  projectId: 'domly-d0f91',
  storageBucket: 'domly-d0f91.firebasestorage.app',
  messagingSenderId: '288330515337',
  appId: '1:288330515337:web:d894db4a58831b07cd9758',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const data = payload.data || {};
  const title = notification.title || 'DOMLY';
  const options = {
    body: notification.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data,
  };
  self.registration.showNotification(title, options);
});
