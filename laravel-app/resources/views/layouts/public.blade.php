<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="description" content="{{ config('clinic.name') }}: {{ config('clinic.subtitle') }}. Schedule, location and contact details.">
    <title>@yield('title', config('clinic.name'))</title>

    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-QWTKZyjpPEjISv5WaRU9OFeRpok6YctnYmDr5pNlyT2bRjXh0JMhjY6hW+ALEwIH" crossorigin="anonymous">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" rel="stylesheet" integrity="sha384-XGjxtQfXaH2tnPFa9x+ruJTuLE3Aa6LhHSWRr1XeTyhezb4abCG4ccI5AkVDxqC+" crossorigin="anonymous">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    @vite(['resources/css/rehabplus-dashboard.css', 'resources/js/public-nav.js'])
</head>
<body class="public-page">
    <header class="public-nav">
        <div class="public-nav-inner">
            <a class="public-brand" href="{{ route('landing') }}">
                <img src="{{ asset('assets/images/rehab-logo.jpg') }}" alt="" class="public-brand-logo">
                <span>{{ config('clinic.name') }}</span>
            </a>

            <nav class="public-links" aria-label="Page sections">
                <a href="{{ route('landing') }}#visit" data-section="visit">Visit us</a>
                @if (! empty($announcements))
                    <a href="{{ route('landing') }}#announcements" data-section="announcements">Announcements</a>
                @endif
                <a href="{{ route('landing') }}#patients" data-section="patients">Remote Monitoring</a>
                <a href="{{ route('landing') }}#classes" data-section="classes">Classes</a>
                <a href="{{ route('landing') }}#packages" data-section="packages">Packages</a>
                <a href="{{ route('landing') }}#about" data-section="about">About us</a>            </nav>

            <a class="btn btn-primary public-login" href="{{ route('login.page') }}" title="For clinic staff only">
                <i class="bi bi-shield-lock me-1"></i>Staff Login
            </a>
        </div>
    </header>

    <main class="public-main">
        @yield('content')
    </main>

    <footer class="public-footer">
        <nav class="public-footer-links" aria-label="Footer">
            @foreach (config('clinic.info_pages') as $slug => $label)
                <a href="{{ route('info.show', $slug) }}">{{ $label }}</a>
            @endforeach
        </nav>

        <div class="public-footer-inner">
            <span>Copyright © {{ date('Y') }} {{ config('clinic.copyright') }}</span>
            <div class="d-flex gap-3">
                <a href="{{ config('clinic.facebook') }}" target="_blank" rel="noopener noreferrer"><i class="bi bi-facebook me-1"></i>Facebook</a>
                <a href="{{ config('clinic.instagram') }}" target="_blank" rel="noopener noreferrer"><i class="bi bi-instagram me-1"></i>Instagram</a>
            </div>
        </div>
    </footer>
</body>
</html>
