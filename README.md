# RehabPlus - Remote PT Monitoring

A comprehensive rehabilitation platform with camera-based pose detection for remote physical therapy monitoring.

## Project Structure

```
rehabplus/
├── lib/                     # Dart source code (Flutter app)
│   ├── main.dart            # App entry point
│   ├── models/              # Data models
│   │   ├── exercise.dart
│   │   ├── exercise_model.dart
│   │   ├── pose_data.dart
│   │   └── session.dart
│   ├── screens/             # UI screens
│   │   ├── login_page.dart
│   │   ├── home_screen.dart
│   │   ├── new_home_screen.dart
│   │   ├── dashboard_screen.dart
│   │   ├── exercise_page.dart
│   │   ├── pose_detector_screen.dart
│   │   ├── history_screen.dart
│   │   ├── profile_screen.dart
│   │   ├── edit_profile_screen.dart
│   │   ├── messages_screen.dart
│   │   ├── notification_page.dart
│   │   ├── forgot_password_screen.dart
│   │   └── demo_screen.dart
│   ├── services/            # Business logic
│   │   ├── app_provider.dart
│   │   ├── compliance_tracker.dart
│   │   ├── form_checker.dart
│   │   ├── pose_estimation_service.dart
│   │   └── session_storage.dart
│   └── widgets/             # Reusable UI components
│       ├── compliance_meter.dart
│       ├── exercise_card.dart
│       ├── pose_overlay.dart
│       └── pose_painter.dart
├── android/                 # Android platform files
├── ios/                     # iOS platform files
├── web/                     # Web platform files
├── linux/                   # Linux desktop config
├── macos/                   # macOS desktop config
├── windows/                 # Windows desktop config
├── test/                    # Unit/widget tests
├── assets/                  # Images, fonts, models
├── pubspec.yaml             # Flutter dependencies
├── analysis_options.yaml    # Lint rules
├── API_CONTRACT.md          # Shared API specification
└── README.md                # This file
```

## Components

### Frontend (Flutter)
- **Patient mobile app** with camera-based pose estimation
- Exercise tracking with real-time form feedback
- Compliance monitoring and progress visualization
- Appointment scheduling and notifications

### Backend - Laravel 11 (`backend/laravel/`)
- Therapist/admin dashboard
- Exercise prescription management
- Patient management
- Appointment scheduling
- Analytics & reporting

### Backend - CodeIgniter 4 (`../RehabPlus-Backend/`)
- Legacy API (branch: `sekendd-admin-dashboard`)
- Exercise library & prescription CRUD
- Shared MySQL database (`rehabplus`)

## Quick Start

### Frontend
```bash
flutter pub get
flutter run
```

### Laravel Backend
```bash
cd backend/laravel
composer install
cp .env.example .env
php artisan key:generate
php artisan migrate --seed
php artisan serve --port=8000
```

### CodeIgniter Backend
```bash
cd ../RehabPlus-Backend
# Requires PHP 8.1+, MySQL
# Configure app/Config/Database.php
php spark serve --port=8081
```

## Databases
- `rehabplus` - CodeIgniter 4 (shared with Flutter via API)
- `rehabplus_laravel` - Laravel 11 (therapist dashboard)
- `rehabplus2` - Groupmate's CodeIgniter 4 instance

## Test Accounts
| Role | Email | Password |
|------|-------|----------|
| Admin | admin@rehabplus.com | admin123 |
| Therapist | therapist@rehabplus.com | admin123 |
| Patient | patient@rehabplus.com | admin123 |

## API Contract
See [API_CONTRACT.md](API_CONTRACT.md) for shared endpoint specifications between frontends and backends.

## Testing
```bash
flutter test            # Unit tests
flutter analyze         # Static analysis
```