@extends('layouts.admin')

@section('title', 'Home')

@section('content')
    @php($tel = preg_replace('/\D/', '', $clinic['phone']))

    <section class="home-hero card shadow-sm border-0 mb-4">
        <div class="home-cover">
            <img src="{{ asset('assets/images/pt.jpg') }}" alt="" class="w-100 h-100">
        </div>
        <div class="home-profile">
            <img src="{{ asset('assets/images/rehab-logo.jpg') }}" alt="{{ $clinic['name'] }} logo" class="home-logo">
            <div class="home-identity">
                <h1 class="home-name">{{ $clinic['name'] }}</h1>
                <p class="home-subtitle">{{ $clinic['subtitle'] }}</p>
            </div>
            <a href="{{ $clinic['facebook'] }}" target="_blank" rel="noopener noreferrer" class="btn btn-primary home-facebook">
                <i class="bi bi-facebook me-2"></i>Visit our Facebook page
            </a>
        </div>
    </section>

    <section class="card shadow-sm border-0 home-info mb-4">
        <div class="row g-0">
            <div class="col-12 col-md-6 col-xl-3 home-info-item">
                <div class="home-icon"><i class="bi bi-clock"></i></div>
                <div>
                    <p class="home-label">Schedule</p>
                    @foreach ($clinic['schedule'] as $slot)
                        <p class="home-value">{{ $slot['days'] }}<span>{{ $slot['hours'] }}</span></p>
                    @endforeach
                </div>
            </div>
            <div class="col-12 col-md-6 col-xl-3 home-info-item">
                <div class="home-icon"><i class="bi bi-geo-alt"></i></div>
                <div>
                    <p class="home-label">Location</p>
                    <p class="home-value">{{ $clinic['location'] }}</p>
                </div>
            </div>
            <div class="col-12 col-md-6 col-xl-3 home-info-item">
                <div class="home-icon"><i class="bi bi-telephone"></i></div>
                <div>
                    <p class="home-label">Contact</p>
                    <a href="tel:{{ $tel }}" class="home-value">{{ $clinic['phone'] }}</a>
                </div>
            </div>
            <div class="col-12 col-md-6 col-xl-3 home-info-item">
                <div class="home-icon"><i class="bi bi-envelope"></i></div>
                <div class="min-w-0">
                    <p class="home-label">Email</p>
                    <a href="mailto:{{ $clinic['email'] }}" class="home-value">{{ $clinic['email'] }}</a>
                </div>
            </div>
        </div>
    </section>

    <h2 class="section-title">Our team</h2>
    @if ($staff === [])
        <div class="card shadow-sm border-0 text-center text-muted py-5 mb-4">No staff accounts yet.</div>
    @else
        <div class="row g-3 mb-4">
            @foreach ($staff as $member)
                <div class="col-6 col-md-4 col-xl-3">
                    <div class="card shadow-sm border-0 h-100 text-center p-3">
                        @if ($member['photoUrl'] !== '')
                            <img src="{{ $member['photoUrl'] }}" alt="{{ $member['name'] }}" class="home-staff-photo mx-auto" loading="lazy">
                        @else
                            <div class="home-staff-initials mx-auto" aria-hidden="true">{{ strtoupper(mb_substr($member['name'] ?: '?', 0, 1)) }}</div>
                        @endif
                        <p class="fw-semibold mb-0 mt-3">{{ $member['name'] }}</p>
                        <p class="text-muted small mb-0">{{ $member['role'] }}</p>
                    </div>
                </div>
            @endforeach
        </div>
    @endif

    <h2 class="section-title">Rewards &amp; recognitions</h2>
    @if ($clinic['awards'] === [])
        <div class="card shadow-sm border-0 text-center text-muted py-5 mb-4">No awards added yet.</div>
    @else
        <div class="row g-3 mb-4">
            @foreach ($clinic['awards'] as $award)
                <div class="col-md-6 col-xl-4">
                    <div class="card shadow-sm border-0 h-100 p-3 d-flex flex-row align-items-start gap-3">
                        <div class="home-icon"><i class="bi {{ $award['icon'] ?? 'bi-award-fill' }}"></i></div>
                        <div class="min-w-0">
                            <p class="fw-semibold mb-0">{{ $award['title'] }}</p>
                            @if (! empty($award['issuer']))
                                <p class="text-muted small mb-1">{{ $award['issuer'] }}</p>
                            @endif
                            @if (! empty($award['year']))
                                <span class="badge bg-success-subtle text-success">{{ $award['year'] }}</span>
                            @endif
                        </div>
                    </div>
                </div>
            @endforeach
        </div>
    @endif
@endsection
