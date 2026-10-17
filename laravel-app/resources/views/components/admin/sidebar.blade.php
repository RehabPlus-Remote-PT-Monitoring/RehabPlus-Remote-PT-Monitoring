<nav class="sidebar d-none d-md-flex flex-column">
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
        @if (in_array(auth()->user()?->role, ['superadmin', 'manager', 'staff', 'therapist'], true))
            <li class="nav-item">
                <a class="nav-link {{ request()->is('messages*') ? 'active' : '' }}" href="{{ route('messages.index') }}">
                    <i class="bi bi-chat-dots-fill"></i>
                    Messages
                </a>
            </li>
        @endif
        <li class="nav-item">
            <a class="nav-link" href="{{ route('appointments.index') }}">
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
        <li class="nav-item">
            <a class="nav-link {{ request()->is('notes') ? 'active' : '' }}" href="{{ url('/notes') }}">
                <i class="bi bi-journal-text"></i>
                Therapy Notes &amp; Care Plans
            </a>
        </li>
        <li class="nav-item">
            <a class="nav-link {{ request()->is('assessments') ? 'active' : '' }}" href="{{ url('/assessments') }}">
                <i class="bi bi-clipboard2-pulse"></i>
                Assessments &amp; Goals
            </a>
        </li>
    </ul>

    @if (auth()->user()?->role === 'superadmin')
        <div class="nav-section mt-4">Admin</div>
        <ul class="nav flex-column">
            <li class="nav-item">
                <a class="nav-link {{ request()->is('users*') ? 'active' : '' }}" href="{{ route('users.index') }}">
                    <i class="bi bi-person-gear"></i>
                    Users
                </a>
            </li>
        </ul>
    @endif
</nav>