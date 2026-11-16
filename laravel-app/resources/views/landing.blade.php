@extends('layouts.public')

@section('title', config('clinic.name'))

@section('content')
    {{-- Reading progress across the top, and a heartbeat under the nav link for the section in view. --}}
    <div class="rehab-progress" aria-hidden="true"><div class="rehab-progress-bar" data-rehab-progress></div></div>
    <style>
        .rehab-progress { position: fixed; top: 0; left: 0; right: 0; height: 3px; z-index: 1100; pointer-events: none; }
        .rehab-progress-bar { height: 100%; width: 100%; transform-origin: left center; transform: scaleX(0); background: linear-gradient(90deg, #5eead4, #0f766e); box-shadow: 0 0 8px rgba(20, 184, 166, .6); }
        .public-links { position: relative; }
        .rehab-nav-indicator { position: absolute; bottom: -12px; left: 0; width: 0; height: 12px; opacity: 0; pointer-events: none; color: #14b8a6; transition: left .35s ease, width .35s ease, opacity .2s ease; }
        .rehab-nav-indicator.is-shown { opacity: 1; }
        .rehab-nav-indicator svg { width: 100%; height: 100%; overflow: visible; }
        .rehab-nav-indicator path { fill: none; stroke: currentColor; stroke-width: 2.2; stroke-linecap: round; stroke-linejoin: round; stroke-dasharray: 100; stroke-dashoffset: 0; }
        .rehab-nav-indicator.is-drawn path { animation: rehab-ecg 1.1s ease-out; }
        @keyframes rehab-ecg { from { stroke-dashoffset: 100; } to { stroke-dashoffset: 0; } }
        @media (prefers-reduced-motion: reduce) {
            .rehab-progress-bar, .rehab-nav-indicator, .rehab-nav-indicator path { transition: none !important; animation: none !important; }
        }
    </style>
    <script nonce="{{ Vite::cspNonce() }}">
        (function () {
            const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
            const bar = document.querySelector('[data-rehab-progress]');
            const links = document.querySelector('.public-links');
            if (!links) return;

            // The heartbeat line is added once and moved under whichever link is active.
            const indicator = document.createElement('span');
            indicator.className = 'rehab-nav-indicator';
            indicator.setAttribute('aria-hidden', 'true');
            indicator.innerHTML = '<svg viewBox="0 0 100 12" preserveAspectRatio="none"><path pathLength="100" d="M0 6 H28 L33 1 L39 11 L45 2 L50 6 H100"/></svg>';
            links.appendChild(indicator);

            function placeIndicator(redraw) {
                const active = links.querySelector('.is-active');
                if (!active) {
                    indicator.classList.remove('is-shown');
                    return;
                }
                indicator.style.left = active.offsetLeft + 'px';
                indicator.style.width = active.offsetWidth + 'px';
                indicator.classList.add('is-shown');
                if (redraw && !reduceMotion) {
                    indicator.classList.remove('is-drawn');
                    void indicator.offsetWidth; // restart the drawing animation
                    indicator.classList.add('is-drawn');
                }
            }

            function updateProgress() {
                if (!bar) return;
                const max = document.documentElement.scrollHeight - window.innerHeight;
                const share = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
                bar.style.transform = 'scaleX(' + share + ')';
            }

            // The nav script toggles is-active as the reader moves; redraw the heartbeat when the section changes.
            let lastActive = null;
            const observer = new MutationObserver(() => {
                const active = links.querySelector('.is-active');
                const id = active ? active.getAttribute('href') : null;
                placeIndicator(id !== lastActive);
                lastActive = id;
            });
            // Watch only the links themselves. Watching the whole list would also see the indicator's own class
            // changes, which set it off again and loop forever (the page freezes).
            links.querySelectorAll('a').forEach((link) => observer.observe(link, { attributes: true, attributeFilter: ['class'] }));

            window.addEventListener('scroll', updateProgress, { passive: true });
            window.addEventListener('resize', () => { updateProgress(); placeIndicator(false); });
            updateProgress();
            placeIndicator(false);
        })();
    </script>

    {{-- The first screen: the hero and the visit card fill the window; announcements start below it on larger screens. --}}
    <style>
        @media (min-width: 768px) {
            .landing-first { min-height: calc(100svh - 7rem); display: flex; flex-direction: column; }
            /* A tall hero, leaving room at the bottom of the first screen for the "Today at Rehab+" heading. */
            .landing-first .home-hero { flex: 0 0 auto; height: calc(100svh - 31rem); min-height: 380px; margin-bottom: 1rem; }
            .landing-first #visit { flex: 0 0 auto; }
            /* The logo is a little larger on the welcome page. */
            .landing-first .home-hero-logo { width: 104px; height: 104px; }
            .landing-first #visit .visit-card { margin-bottom: 0 !important; }
        }
    </style>
    <div class="landing-first">
        @include('partials.clinic-hero')

        <div id="visit">
            @include('partials.stories')
            @include('partials.clinic-info')
        </div>
    </div>

    @include('partials.announcements', ['announcements' => $announcements])

    @include('partials.health-services')

    @include('partials.for-patients')

    <div id="classes">
        @include('partials.classes')
    </div>

    <div id="packages">
        @include('partials.clinic-packages')
    </div>

    <div id="about">
        @include('partials.about')
        @include('partials.staff-board')
        @include('partials.clinic-awards')
    </div>

    @include('partials.contact-cta')
@endsection
