<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, interactive-widget=resizes-content">
    <meta name="theme-color" content="#f6f8fb" id="themeColor">
    <title>@yield('title', 'RehabPlus Dashboard')</title>

    {{-- Apply the saved theme before the page paints, so dark mode doesn't flash white. --}}
    <script nonce="{{ Vite::cspNonce() }}">
        if (localStorage.getItem('rehabplus-theme') === 'dark') {
            document.documentElement.classList.add('dark-mode');
            document.getElementById('themeColor').content = '#10172a';
        }
    </script>

    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-QWTKZyjpPEjISv5WaRU9OFeRpok6YctnYmDr5pNlyT2bRjXh0JMhjY6hW+ALEwIH" crossorigin="anonymous">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" rel="stylesheet" integrity="sha384-XGjxtQfXaH2tnPFa9x+ruJTuLE3Aa6LhHSWRr1XeTyhezb4abCG4ccI5AkVDxqC+" crossorigin="anonymous">
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js" integrity="sha384-JUh163oCRItcbPme8pYnROHQMC6fNKTBWtRG3I3I0erJkzNgL7uxKlNwcrcFKeqF" crossorigin="anonymous" nonce="{{ Vite::cspNonce() }}"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    @vite(['resources/css/rehabplus-dashboard.css', 'resources/js/rehabplus-dashboard.js'])
</head>
<body>
    <nav class="navbar d-flex justify-content-between align-items-center flex-nowrap" id="topbar">
        <div class="d-flex align-items-center gap-2 min-w-0">
            {{-- Phones: opens the sidebar as a slide-out drawer. --}}
            <button type="button" class="nav-toggle d-md-none" id="navToggle" aria-label="Open menu" aria-controls="sidebar" aria-expanded="false">
                <i class="bi bi-list"></i>
            </button>
            <a class="navbar-brand d-flex align-items-center gap-2" href="{{ route('dashboard') }}">
                <i class="bi bi-heart-pulse-fill"></i>
                RehabPlus
            </a>
        </div>

        <div class="d-flex align-items-center gap-2 gap-md-3">
            <span class="top-date d-none d-md-inline">{{ now()->format('F j, Y') }}</span>

            <button type="button" class="theme-toggle" id="themeToggle" title="Toggle dark mode" aria-label="Toggle dark mode">
                <i class="bi bi-moon-fill"></i>
            </button>

            <div class="user-chip" title="{{ auth()->user()->name ?? '' }}">
                <div class="user-avatar">{{ strtoupper(substr(auth()->user()->name ?? 'U', 0, 1)) }}</div>
                <div class="user-chip-text">
                    <div class="fw-bold">{{ auth()->user()->name ?? '' }}</div>
                    <small class="text-muted">{{ auth()->user()?->roleLabel() }}</small>
                </div>
            </div>

            <form method="POST" action="{{ route('logout') }}">
                @csrf
                <button type="submit" class="btn btn-outline-secondary rounded-pill px-3 logout-btn" aria-label="Logout">
                    <i class="bi bi-box-arrow-right"></i>
                    <span class="logout-label">Logout</span>
                </button>
            </form>
        </div>
    </nav>

    <div class="sidebar-scrim" id="sidebarScrim" aria-hidden="true"></div>

    <div class="d-flex">
        <nav class="sidebar d-flex flex-column" id="sidebar" aria-label="Main menu" tabindex="-1">
            <div class="sidebar-head">
                <span class="navbar-brand d-flex align-items-center gap-2">
                    <i class="bi bi-heart-pulse-fill"></i>
                    RehabPlus
                </span>
                <button type="button" class="nav-toggle" id="navClose" aria-label="Close menu">
                    <i class="bi bi-x-lg"></i>
                </button>
            </div>

            <div class="nav-section">Overview</div>
            <ul class="nav flex-column">
                <li class="nav-item">
                    <a class="nav-link {{ request()->routeIs('dashboard') ? 'active' : '' }}" href="{{ route('dashboard') }}">
                        <i class="bi bi-speedometer2"></i>
                        Dashboard
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link {{ request()->routeIs('analytics') ? 'active' : '' }}" href="{{ route('analytics') }}">
                        <i class="bi bi-graph-up-arrow"></i>
                        Reports &amp; Analytics
                    </a>
                </li>
            </ul>

            <div class="nav-section mt-4">Management</div>
            <ul class="nav flex-column">
                <li class="nav-item">
                    <a class="nav-link {{ request()->is('patients*') ? 'active' : '' }}" href="{{ route('patients.index') }}">
                        <i class="bi bi-people-fill"></i>
                        Patients
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link {{ request()->is('messages*') ? 'active' : '' }}" href="{{ route('messages.index') }}">
                        <i class="bi bi-chat-dots-fill"></i>
                        Messages
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link {{ request()->routeIs('appointments.*') || request()->is('appointments*') ? 'active' : '' }}" href="{{ route('appointments.index') }}">
                        <i class="bi bi-calendar-check"></i>
                        Appointments
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link {{ request()->is('billing') ? 'active' : '' }}" href="{{ url('/billing') }}">
                        <i class="bi bi-credit-card"></i>
                        Billing and Payment Records
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link {{ request()->is('inventory') ? 'active' : '' }}" href="{{ url('/inventory') }}">
                        <i class="bi bi-box-seam"></i>
                        Inventory and Supplies
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link {{ request()->is('schedule') ? 'active' : '' }}" href="{{ url('/schedule') }}">
                        <i class="bi bi-calendar-week"></i>
                        Staff Schedule
                    </a>
                </li>
                @if (auth()->user()?->isClinician())
                    <li class="nav-item">
                        <a class="nav-link {{ request()->is('notes') ? 'active' : '' }}" href="{{ route('notes') }}">
                            <i class="bi bi-journal-text"></i>
                            Therapy Notes &amp; Care Plans
                        </a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link {{ request()->is('assessments') ? 'active' : '' }}" href="{{ route('assessments') }}">
                            <i class="bi bi-clipboard2-pulse"></i>
                            Assessments &amp; Goals
                        </a>
                    </li>
                @endif
            </ul>

            @if (auth()->user()?->isAdmin())
                <div class="nav-section mt-4">Admin</div>
                <ul class="nav flex-column">
                    <li class="nav-item">
                        <a class="nav-link {{ request()->is('users*') ? 'active' : '' }}" href="{{ route('users.index') }}">
                            <i class="bi bi-person-gear"></i>
                            Staff Accounts
                        </a>
                    </li>
                </ul>
            @endif
        </nav>

        <main class="main-content" id="mainContent">
            @yield('content')
        </main>
    </div>
</body>
</html>