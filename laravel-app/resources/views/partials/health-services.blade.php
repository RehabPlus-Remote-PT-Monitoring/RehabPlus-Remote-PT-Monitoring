{{-- Health services for recovery: the clinic's services, in terms of what they help with. Wording follows config/clinic.php and the about section. --}}
<style>
    .health-section { margin: 2.5rem 0; }
    .health-head { margin-bottom: 1.25rem; }
    .health-title { margin: 0 0 .25rem; font-size: 1.5rem; font-weight: 800; letter-spacing: -.01em; }
    .health-sub { margin: 0; color: var(--muted, #64748b); max-width: 52rem; }
    .health-grid { display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); }
    .health-card { position: relative; overflow: hidden; border-radius: 1.1rem; padding: 1.4rem; background: var(--card, #fff); border: 1px solid var(--border); display: flex; flex-direction: column; gap: .6rem; transition: transform .2s ease, box-shadow .2s ease; }
    .health-card:hover { transform: translateY(-3px); box-shadow: 0 14px 30px rgba(15, 23, 42, .09); }
    .health-card::after { content: ''; position: absolute; right: -40px; top: -40px; width: 120px; height: 120px; border-radius: 50%; background: radial-gradient(circle, rgba(45, 212, 191, .18), transparent 70%); pointer-events: none; }
    .health-chip { display: grid; place-items: center; width: 48px; height: 48px; border-radius: 1rem; background: linear-gradient(135deg, #2dd4bf, #0f766e); color: #fff; font-size: 1.25rem; box-shadow: 0 8px 18px rgba(15, 118, 110, .3); }
    .health-card h3 { margin: .2rem 0 0; font-size: 1.05rem; font-weight: 800; }
    .health-card p { margin: 0; color: var(--text, #334155); font-size: .94rem; line-height: 1.5; }
    .health-tag { align-self: flex-start; font-size: .7rem; font-weight: 800; letter-spacing: .07em; text-transform: uppercase; color: #0f766e; background: #ccfbf1; border-radius: 999px; padding: .2rem .6rem; }
    .health-link { margin-top: auto; align-self: flex-start; font-weight: 700; color: #0f766e; text-decoration: none; }
    .health-link:hover { text-decoration: underline; }
    @media (prefers-reduced-motion: reduce) { .health-card { transition: none; } .health-card:hover { transform: none; } }
</style>

<section class="health-section" aria-labelledby="health-title" data-health-services>
    <div class="health-head">
        <h2 class="health-title" id="health-title">Health services for your recovery</h2>
        <p class="health-sub">Rehab+ combines evidence-based physical therapy with the principles of Pilates. Choose the kind of care that fits where you are in your recovery.</p>
    </div>

    <div class="health-grid">
        <article class="health-card">
            <span class="health-tag">Rehabilitation</span>
            <span class="health-chip"><i class="bi bi-heart-pulse-fill" aria-hidden="true"></i></span>
            <h3>Physical therapy</h3>
            <p>Care from licensed physical therapists, planned around your condition, your goals, and how you move.</p>
            <a class="health-link" href="{{ route('landing') }}#packages">See the rehab packages <i class="bi bi-arrow-right" aria-hidden="true"></i></a>
        </article>

        <article class="health-card">
            <span class="health-tag">Therapist-led</span>
            <span class="health-chip"><i class="bi bi-activity" aria-hidden="true"></i></span>
            <h3>Pilatherapy</h3>
            <p>A therapist-led program that combines Pilates-based movement with clinical physical therapy. Designed to relieve pain, restore movement, and build strength.</p>
            <a class="health-link" href="{{ route('landing') }}#classes">See the classes <i class="bi bi-arrow-right" aria-hidden="true"></i></a>
        </article>

        <article class="health-card">
            <span class="health-tag">Private</span>
            <span class="health-chip"><i class="bi bi-person-check-fill" aria-hidden="true"></i></span>
            <h3>Clinical Pilates, one-on-one</h3>
            <p>A private session tailored to your body and goals. Ideal for focused progress and for working around an injury.</p>
            <a class="health-link" href="{{ route('landing') }}#classes">See the classes <i class="bi bi-arrow-right" aria-hidden="true"></i></a>
        </article>

        <article class="health-card">
            <span class="health-tag">At home</span>
            <span class="health-chip"><i class="bi bi-phone-fill" aria-hidden="true"></i></span>
            <h3>Remote monitoring</h3>
            <p>Do your prescribed home exercises with camera guidance in the RehabPlus app. Your therapist follows your progress from the clinic.</p>
            <a class="health-link" href="{{ route('remote-monitoring') }}">Learn about the app <i class="bi bi-arrow-right" aria-hidden="true"></i></a>
        </article>
    </div>
</section>
