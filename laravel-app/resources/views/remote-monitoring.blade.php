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

    <section class="rm-demo" aria-labelledby="rm-demo-title">
        <h2 id="rm-demo-title" class="section-title">See the app in action</h2>
        <div class="rm-player">
            <video id="rm-video" class="rm-video" controls playsinline preload="metadata"
                   aria-describedby="rm-demo-note">
                <source src="{{ asset('assets/videos/rehabplus-remote-monitoring-demo.mp4') }}" type="video/mp4">
                Your browser cannot play this video.
                <a href="{{ asset('assets/videos/rehabplus-remote-monitoring-demo.mp4') }}">Download the demo video</a>.
            </video>
            <div class="rm-skip-row" role="group" aria-label="Skip video">
                <button type="button" class="rm-skip-btn" data-skip="-10">
                    <i class="bi bi-skip-backward-fill" aria-hidden="true"></i> Back 10 seconds
                </button>
                <button type="button" class="rm-skip-btn" data-skip="10">
                    Forward 10 seconds <i class="bi bi-skip-forward-fill" aria-hidden="true"></i>
                </button>
            </div>
        </div>
        <p id="rm-demo-note" class="rm-demo-note">
            <i class="bi bi-info-circle me-1" aria-hidden="true"></i>Use the play button, or drag the bar to move through the video.
        </p>
    </section>

    {{-- A live pose check, from the app's exercise screen --}}
    <section class="rm-pose" aria-labelledby="rm-pose-title">
        <style>
            .rm-pose { display: grid; gap: 2rem; align-items: center; grid-template-columns: 1fr; margin: 2.5rem 0; padding: 1.75rem; border: 1px solid #ccfbf1; border-radius: 1.5rem; background: linear-gradient(135deg, #f0fdfa, #ecfeff); }
            @media (min-width: 900px) { .rm-pose { grid-template-columns: minmax(260px, 330px) 1fr; gap: 3rem; padding: 2.5rem; } }
            .rm-phone { width: min(300px, 100%); margin: 0 auto; padding: .6rem; border-radius: 2.4rem; background: #0f172a; box-shadow: 0 24px 50px rgba(15, 23, 42, .28); }
            .rm-phone img { display: block; width: 100%; height: auto; border-radius: 1.8rem; }
            .rm-pose-eyebrow { margin: 0 0 .35rem; font-size: .78rem; font-weight: 800; letter-spacing: .1em; text-transform: uppercase; color: #0d9488; }
            .rm-pose-points { list-style: none; margin: 1.25rem 0 0; padding: 0; display: grid; gap: .7rem; }
            .rm-pose-points li { display: flex; gap: .8rem; align-items: center; padding: .8rem 1rem; border-radius: 1rem; background: #fff; box-shadow: 0 4px 14px rgba(15, 23, 42, .06); }
            .rm-pose-points i { flex-shrink: 0; width: 2rem; height: 2rem; display: grid; place-items: center; border-radius: .6rem; background: linear-gradient(135deg, #ccfbf1, #f0fdfa); color: #0f766e; font-size: 1rem; }
        </style>

        <div class="rm-phone">
            <img src="{{ asset('assets/images/app/app-pose.jpg') }}" alt="The RehabPlus Mobile App pose check: a patient stands facing the camera while the app draws a skeleton over their body, with the reps counted and the joint angle shown." loading="lazy">
        </div>

        <div>
            <p class="rm-pose-eyebrow">Real-time guidance</p>
            <h2 id="rm-pose-title" class="section-title mt-0">A pose check while you exercise</h2>
            <p class="mb-0">The app draws a skeleton over your body as you move, so you can see whether you are in the right position.</p>
            <ul class="rm-pose-points">
                <li><i class="bi bi-person-arms-up" aria-hidden="true"></i><span>Stand facing the camera, with your upper body and both arms in view.</span></li>
                <li><i class="bi bi-123" aria-hidden="true"></i><span>See your reps counted against your target, such as 0 of 10.</span></li>
                <li><i class="bi bi-rulers" aria-hidden="true"></i><span>Watch the joint angle update live as you move.</span></li>
                <li><i class="bi bi-cast" aria-hidden="true"></i><span>Too far from the screen to read it? Cast it to a TV or laptop.</span></li>
            </ul>
        </div>
    </section>

    <script>
        (function () {
            var video = document.getElementById('rm-video');
            if (!video) {
                return;
            }
            document.querySelectorAll('.rm-skip-btn').forEach(function (button) {
                button.addEventListener('click', function () {
                    var step = Number(button.getAttribute('data-skip')) || 0;
                    var duration = isFinite(video.duration) ? video.duration : Infinity;
                    video.currentTime = Math.min(Math.max(video.currentTime + step, 0), duration);
                });
            });
        })();
    </script>

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
