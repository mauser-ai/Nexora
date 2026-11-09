importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCyYzngYhHCPBpbQDInuEwhaRUxrgyXO2s',
  appId: '1:362917162978:web:20ea08e0ff8f55702793bb',
  messagingSenderId: '362917162978',
  projectId: 'gussoni-d3153',
  authDomain: 'gussoni-d3153.firebaseapp.com',
  storageBucket: 'gussoni-d3153.firebasestorage.app',
  measurementId: 'G-E2NVE2CDXF',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const title = notification.title || 'Nexora';
  const options = {
    body: notification.body || 'Hai una nuova notifica.',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data || {},
  };

  self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetUrl = '/';
  event.waitUntil(
    clients.matchAll({type: 'window', includeUncontrolled: true}).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
      return undefined;
    }),
  );
});
