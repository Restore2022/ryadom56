# Push-уведомления (Firebase Cloud Messaging HTTP v1)

Legacy Server Key в вашем проекте **отключён** — нужен только HTTP v1.

## 1. Клиент (уже сделано)
- `mobile/android/app/google-services.json` из Firebase
- Gradle plugin `com.google.gms.google-services`

## 2. Service Account (обязательно для пушей с сервера)

Экран Cloud Messaging с Sender ID `404074095424` — это **не** ключ для сервера.
Web Push certificates (пара ключей VAPID) тоже не нужны для Android.

Нужен JSON **Firebase Admin SDK**:

1. На той же странице нажмите **Manage Service Accounts** справа от Sender ID  
   **или** Project settings → вкладка **Service accounts**
2. Firebase Admin SDK → **Generate new private key**
3. Скачается JSON вроде `ryadom56-firebase-adminsdk-xxxxx.json`  
   (это **не** `google-services.json` и не Web Push key pair)
4. Положите его на VPS:

```bash
scp firebase-adminsdk-xxxxx.json root@155.212.174.201:/opt/ryadom56/backend/data/firebase-service-account.json
chmod 600 /opt/ryadom56/backend/data/firebase-service-account.json
```

5. В `/opt/ryadom56/backend/.env` добавьте:

```
FCM_PROJECT_ID=ryadom56
FCM_SERVICE_ACCOUNT_FILE=/opt/ryadom56/backend/data/firebase-service-account.json
```

6. Установите зависимости и перезапустите:

```bash
cd /opt/ryadom56 && ./venv/bin/pip install -q google-auth requests
systemctl restart ryadom56
```

## 3. Что шлётся
- `listing_message` — новое сообщение в чате
- `listing_approved` / `listing_rejected` — модерация объявления
- `district_alert` — срочное/активное оповещение района

## 4. Проверка
После входа в приложение токен уходит на `/auth/device`.  
Создайте тестовый алерт в админке или напишите в чат — на телефоне должен прийти push.
