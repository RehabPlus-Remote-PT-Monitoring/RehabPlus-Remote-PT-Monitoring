<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    // Firebase (Auth, Firestore, FCM): the dashboard's data store and logins.
    // FIREBASE_CREDENTIALS is the path to the service-account JSON; keep that
    // file outside the repo. On hosts without a disk (Vercel), put the JSON
    // itself (raw or base64) in FIREBASE_CREDENTIALS_JSON instead; it wins
    // when set. FIREBASE_API_KEY is the project's Web API key (public, same as
    // in the app's google-services.json); it's only used to check staff
    // passwords at login.
    'firebase' => [
        'credentials' => env('FIREBASE_CREDENTIALS'),
        'credentials_json' => env('FIREBASE_CREDENTIALS_JSON'),
        'project_id' => env('FIREBASE_PROJECT_ID', 'rehabplus-80675'),
        'api_key' => env('FIREBASE_API_KEY'),

        // Transport tuning (App\Services\Firebase\FirebaseTransport).
        'timeout' => (int) env('FIREBASE_TIMEOUT', 15),                 // seconds per call
        'connect_timeout' => (int) env('FIREBASE_CONNECT_TIMEOUT', 5),  // seconds to connect
        'max_attempts' => (int) env('FIREBASE_MAX_ATTEMPTS', 3),        // incl. the first try; reads only
        'retry_backoff_ms' => (int) env('FIREBASE_RETRY_BACKOFF_MS', 150),
        'max_parallel' => (int) env('FIREBASE_MAX_PARALLEL', 10),       // calls in flight at once
        'slow_ms' => (int) env('FIREBASE_SLOW_MS', 1500),               // log a warning above this
    ],

    // Evening exercise reminders (App\Services\Patient\ExerciseReminderService).
    // A GitHub Actions schedule calls POST /cron/exercise-reminders at 6 PM
    // with "Authorization: Bearer <CRON_SECRET>". Without a secret the route
    // refuses every call. Reminders only go out from send_after_hour on.
    'reminders' => [
        'cron_secret' => env('CRON_SECRET'),
        'timezone' => env('REMINDER_TIMEZONE', 'Asia/Manila'),
        'send_after_hour' => (int) env('REMINDER_SEND_AFTER_HOUR', 18),
    ],

    // Terms of Service / Privacy Policy version the patient app currently asks
    // patients to accept (App\Services\Patient\ConsentService). MUST match
    // LegalInfo.version in the app repo's lib/legal/legal_info.dart: when the
    // app ships new terms, bump this too, or the profile page will call the
    // new version "current" too late (or flag patients as outdated too early).
    'legal' => [
        'consent_version' => env('LEGAL_CONSENT_VERSION', '2026-10-18'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

];
