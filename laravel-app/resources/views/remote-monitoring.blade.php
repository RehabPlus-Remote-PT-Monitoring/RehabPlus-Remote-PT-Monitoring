@extends('layouts.public')

@section('title', 'RehabPlus Remote Monitoring')

@section('content')
    <a href="{{ route('landing') }}" class="back-link small text-decoration-none d-inline-block mb-3"><i class="bi bi-arrow-left me-1"></i>Back to home</a>

    <section class="rm-hero" aria-labelledby="rm-title">
        <div class="rm-hero-text">
            <p class="rm-eyebrow">Exclusive patient access</p>
            <h1 id="rm-title" class="rm-title">RehabPlus Remote Monitoring</h1>
            <p class="rm-lead">
                The RehabPlus Mobile App helps enrolled patients of {{ config('clinic.name') }} do their prescribed home
                exercises with real-time guidance, and helps our licensed physical therapists monitor recovery progress
                remotely.
            </p>
            <a href="{{ route('landing') }}#visit" class="rm-btn">Ask about access</a>
        </div>

        <div class="rm-gallery" role="group" aria-label="Screens from the RehabPlus Mobile App">
            <img src="{{ asset('assets/images/app/app-login.jpg') }}" alt="RehabPlus Mobile App sign-in screen" class="rm-shot" loading="lazy">
            <img src="{{ asset('assets/images/app/app-home.jpg') }}" alt="RehabPlus Mobile App home screen" class="rm-shot rm-shot-center" loading="lazy">
            <img src="{{ asset('assets/images/app/app-exercises.jpg') }}" alt="RehabPlus Mobile App exercise list" class="rm-shot" loading="lazy">
        </div>
    </section>

    <h2 class="section-title">How it works</h2>
    <div class="rm-steps">
        @foreach (config('clinic.remote_monitoring.steps') as $step)
            <div class="rm-step">
                <span class="rm-step-number" aria-hidden="true">{{ $loop->iteration }}</span>
                <h3>{{ $step['title'] }}</h3>
                <p>{{ $step['text'] }}</p>
            </div>
        @endforeach
    </div>

    <h2 class="section-title">What the app does</h2>
    <div class="rm-feature-grid">
        @foreach (config('clinic.remote_monitoring.features') as $feature)
            <div class="rm-feature">
                <span class="rm-feature-icon" aria-hidden="true"><i class="bi {{ $feature['icon'] }}"></i></span>
                <h3>{{ $feature['title'] }}</h3>
                <p>{{ $feature['text'] }}</p>
            </div>
        @endforeach
    </div>

    <h2 class="section-title">Who can use it</h2>
    <div class="rm-access">
        <ul class="rm-access-points">
            <li><i class="bi bi-check-circle-fill" aria-hidden="true"></i><span>Prescribed by your therapist</span></li>
            <li><i class="bi bi-check-circle-fill" aria-hidden="true"></i><span>For enrolled patients only, in a rehabilitation package</span></li>
            <li><i class="bi bi-check-circle-fill" aria-hidden="true"></i><span>Not available for public download</span></li>
        </ul>
        <p class="rm-access-note">
            <i class="bi bi-info-circle me-1" aria-hidden="true"></i>There is no public registration. Patient accounts are created
            only by clinic staff, after a face-to-face clinical assessment. When you first open the app, you will review and
            accept its Terms and Privacy Policy.
        </p>
    </div>

    <section class="rm-cta mt-5" aria-labelledby="rm-cta-title">
        <h2 id="rm-cta-title" class="rm-cta-title">Not sure if the app is right for you?</h2>
        <p class="rm-cta-text">Ask us about access and your eligibility. Our team will be glad to help.</p>
        <a href="{{ route('landing') }}#visit" class="rm-btn rm-btn-solid">Contact us</a>
    </section>
@endsection
