{{-- Visit us: schedule with today's status, location, contact and email, and what to bring. Needs $clinic (config/clinic.php). --}}
@php
    $now = \Carbon\CarbonImmutable::now(config('app.timezone'));
    $nowTime = $now->format('H:i');
    $todaySlot = collect($clinic['schedule'])->first(fn ($slot) => in_array($now->dayOfWeekIso, $slot['open_days'] ?? [], true));
    $isOpen = $todaySlot !== null && $nowTime >= $todaySlot['from'] && $nowTime < $todaySlot['to'];
    $clock = fn (string $hm) => \Carbon\CarbonImmutable::createFromFormat('H:i', $hm)->format('g:ia');
    if ($isOpen) {
        $status = 'Open now · closes '.$clock($todaySlot['to']);
    } elseif ($todaySlot !== null && $nowTime < $todaySlot['from']) {
        $status = 'Closed now · opens '.$clock($todaySlot['from']).' today';
    } else {
        $status = 'Closed now';
    }
    $mailLink = 'https://mail.google.com/mail/?view=cm&fs=1&to='.rawurlencode($clinic['email']);
@endphp

<style>
    .visit-card { background: var(--card, #fff); border: 1px solid var(--border); border-radius: 1.25rem; padding: 1.5rem; }
    .visit-head { margin-bottom: 1.25rem; display: flex; flex-wrap: wrap; align-items: flex-end; justify-content: space-between; gap: 1rem; }
    .visit-head-actions { display: flex; flex-wrap: wrap; gap: .6rem; }
    .visit-head-actions .btn { border-radius: .8rem; font-weight: 600; }
    .visit-title { margin: 0 0 .2rem; font-size: 1.5rem; font-weight: 800; letter-spacing: -.01em; }
    .visit-sub { margin: 0; color: var(--muted, #64748b); font-size: .95rem; }
    .visit-tiles { display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); }
    .visit-tile { position: relative; border: 1px solid var(--border); border-radius: 1rem; padding: 1.15rem; display: flex; flex-direction: column; gap: .7rem; min-width: 0; background: var(--card, #fff); transition: transform .2s ease, box-shadow .2s ease; }
    .visit-tile:hover { transform: translateY(-2px); box-shadow: 0 10px 24px rgba(15, 23, 42, .08); }
    .visit-tile.span-2 { grid-column: span 2; }
    @media (max-width: 767px) { .visit-tile.span-2 { grid-column: auto; } }
    .visit-tile-head { display: flex; align-items: center; gap: .7rem; }
    .visit-tile-head .label { margin: 0; font-size: .72rem; font-weight: 800; letter-spacing: .09em; text-transform: uppercase; color: var(--muted, #64748b); }
    /* Modern icon chip: a soft gradient tile with a solid glyph. */
    .visit-chip { display: grid; place-items: center; width: 44px; height: 44px; border-radius: .9rem; background: linear-gradient(135deg, #2dd4bf, #0f766e); color: #fff; font-size: 1.15rem; box-shadow: 0 6px 14px rgba(15, 118, 110, .28); flex-shrink: 0; }
    .visit-value { margin: 0; font-weight: 700; line-height: 1.4; overflow-wrap: anywhere; color: var(--text, #0f172a); }
    .visit-status { display: inline-flex; align-items: center; gap: .45rem; padding: .3rem .75rem; border-radius: 999px; font-size: .82rem; font-weight: 700; }
    .visit-status::before { content: ''; width: .55rem; height: .55rem; border-radius: 50%; background: currentColor; }
    .visit-status-open { background: #dcfce7; color: #166534; }
    .visit-status-open::before { animation: visit-pulse 1.8s ease-in-out infinite; }
    .visit-status-closed { background: #f1f5f9; color: #475569; }
    @keyframes visit-pulse { 0%, 100% { box-shadow: 0 0 0 0 rgba(22, 101, 52, .45); } 50% { box-shadow: 0 0 0 6px rgba(22, 101, 52, 0); } }
    .visit-list { list-style: none; margin: 0; padding: 0; display: grid; gap: .35rem; }
    .visit-list li { display: flex; align-items: center; flex-wrap: wrap; gap: .4rem; padding: .4rem .6rem; border-radius: .6rem; font-size: .92rem; }
    .visit-list li.is-today { background: linear-gradient(90deg, #ccfbf1, #f0fdfa); }
    .visit-list .hours { color: var(--muted, #64748b); }
    .visit-today { margin-left: auto; font-size: .7rem; font-weight: 800; text-transform: uppercase; letter-spacing: .06em; color: #0f766e; }
    .visit-list .visit-status { flex-basis: 100%; margin-top: .15rem; font-size: .78rem; padding: .2rem .6rem; }
    .visit-actions { margin-top: auto; display: flex; }
    .visit-actions .btn { width: 100%; font-size: .85rem; border-radius: .7rem; }

    /* Before you come: a mascot that points at the list. */
    .visit-tips { margin-top: 1.5rem; display: flex; align-items: center; gap: 1.25rem; flex-wrap: wrap; }
    .visit-mascot { width: 130px; flex-shrink: 0; }
    .visit-mascot svg { width: 100%; height: auto; display: block; }
    .visit-bubble { position: relative; flex: 1 1 320px; border-radius: 1.1rem; padding: 1.1rem 1.25rem; background: linear-gradient(135deg, #f0fdfa, #ecfeff); border: 1px solid #ccfbf1; }
    .visit-bubble::before { content: ''; position: absolute; left: -10px; top: 26px; width: 18px; height: 18px; background: #f0fdfa; border-left: 1px solid #ccfbf1; border-bottom: 1px solid #ccfbf1; transform: rotate(45deg); }
    .visit-tips-title { margin: 0 0 .6rem; font-weight: 800; color: #115e59; font-size: 1rem; }
    .visit-tips ul { list-style: none; margin: 0; padding: 0; display: grid; gap: .5rem; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); }
    .visit-tips li { display: flex; gap: .55rem; align-items: flex-start; font-size: .92rem; color: var(--text, #0f172a); }
    .visit-tips li i { color: #0d9488; font-size: 1.05rem; margin-top: .1rem; }
    @media (prefers-reduced-motion: reduce) {
        .visit-tile { transition: none; }
        .visit-tile:hover { transform: none; }
        .visit-status-open::before { animation: none; }
    }
</style>

<section class="visit-card shadow-sm mb-4" aria-labelledby="visit-heading" data-visit>
    <div class="visit-head">
        <div>
            <h2 class="visit-title" id="visit-heading">Visit us</h2>
            <p class="visit-sub">Walk in during clinic hours, or send us a message first for inquiries and appointments.</p>
        </div>
    </div>

    <div class="visit-tiles">
        {{-- Schedule: today's status sits on today's own row --}}
        <article class="visit-tile span-2">
            <div class="visit-tile-head">
                <span class="visit-chip"><i class="bi bi-clock-fill" aria-hidden="true"></i></span>
                <p class="label">Schedule</p>
            </div>
            <ul class="visit-list">
                @foreach ($clinic['schedule'] as $slot)
                    @php($isToday = $todaySlot === $slot)
                    <li class="{{ $isToday ? 'is-today' : '' }}">
                        <strong>{{ $slot['days'] }}</strong>
                        <span class="hours">{{ $slot['hours'] }}</span>
                        @if ($isToday)
                            <span class="visit-today">Today</span>
                            <span class="visit-status {{ $isOpen ? 'visit-status-open' : 'visit-status-closed' }}" data-visit-status="{{ $isOpen ? 'open' : 'closed' }}">{{ $status }}</span>
                        @endif
                    </li>
                @endforeach
            </ul>
            @if ($todaySlot === null)
                <span class="visit-status visit-status-closed" data-visit-status="closed">{{ $status }}</span>
            @endif
        </article>

        {{-- Location --}}
        <article class="visit-tile">
            <div class="visit-tile-head">
                <span class="visit-chip"><i class="bi bi-geo-alt-fill" aria-hidden="true"></i></span>
                <p class="label">Location</p>
            </div>
            <p class="visit-value">{{ $clinic['location'] }}</p>
            <div class="visit-actions">
                <a href="{{ $clinic['map_url'] }}" target="_blank" rel="noopener noreferrer" class="btn btn-sm btn-outline-primary"><i class="bi bi-signpost-2-fill me-1" aria-hidden="true"></i>Get directions</a>
            </div>
        </article>

        {{-- Contact: the number only, no button --}}
        <article class="visit-tile">
            <div class="visit-tile-head">
                <span class="visit-chip"><i class="bi bi-telephone-fill" aria-hidden="true"></i></span>
                <p class="label">Contact</p>
            </div>
            <p class="visit-value">{{ $clinic['phone'] }}</p>
        </article>

        {{-- Email --}}
        <article class="visit-tile span-2">
            <div class="visit-tile-head">
                <span class="visit-chip"><i class="bi bi-envelope-fill" aria-hidden="true"></i></span>
                <p class="label">Email</p>
            </div>
            <p class="visit-value">{{ $clinic['email'] }}</p>
            <div class="visit-actions">
                <a href="{{ $mailLink }}" class="btn btn-sm btn-outline-primary" target="_blank" rel="noopener noreferrer"><i class="bi bi-send-fill me-1" aria-hidden="true"></i>Send an email</a>
            </div>
        </article>
    </div>

    {{-- Before you come: the mascot points at the list (the clinic's FAQ) --}}
    <div class="visit-tips">
        <div class="visit-mascot" aria-hidden="true">
            <svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg" role="img">
                <ellipse cx="100" cy="190" rx="58" ry="7" fill="#0f172a" opacity=".12"/>
                <!-- legs -->
                <rect x="72" y="136" width="22" height="50" rx="11" fill="#115e59"/>
                <rect x="106" y="136" width="22" height="50" rx="11" fill="#115e59"/>
                <ellipse cx="83" cy="188" rx="14" ry="7" fill="#0f172a"/>
                <ellipse cx="117" cy="188" rx="14" ry="7" fill="#0f172a"/>
                <!-- raised arm, reaching toward the list -->
                <path d="M140 108 Q162 96 182 86" fill="none" stroke="#14b8a6" stroke-width="18" stroke-linecap="round"/>
                <circle cx="186" cy="84" r="10" fill="#fcd9b8"/>
                <!-- hanging arm -->
                <path d="M56 108 L56 150" fill="none" stroke="#14b8a6" stroke-width="18" stroke-linecap="round"/>
                <circle cx="56" cy="160" r="9" fill="#fcd9b8"/>
                <!-- torso: a teal polo with a white collar and a small clinic cross -->
                <rect x="60" y="96" width="80" height="62" rx="24" fill="#14b8a6"/>
                <path d="M88 96 L100 110 L112 96 Z" fill="#ffffff"/>
                <rect x="98" y="122" width="4" height="14" rx="2" fill="#ffffff"/>
                <rect x="95" y="125" width="10" height="4" rx="2" fill="#ffffff"/>
                <!-- neck and head -->
                <rect x="91" y="80" width="18" height="20" rx="6" fill="#fcd9b8"/>
                <circle cx="100" cy="58" r="34" fill="#fcd9b8"/>
                <!-- hair -->
                <path d="M66 54 Q66 24 100 23 Q134 24 134 54 Q124 40 100 40 Q76 40 66 54 Z" fill="#0f172a"/>
                <!-- face -->
                <circle cx="88" cy="60" r="4" fill="#0f172a"/>
                <circle cx="112" cy="60" r="4" fill="#0f172a"/>
                <circle cx="79" cy="70" r="5" fill="#fca5a5" opacity=".6"/>
                <circle cx="121" cy="70" r="5" fill="#fca5a5" opacity=".6"/>
                <path d="M90 72 Q100 81 110 72" fill="none" stroke="#0f172a" stroke-width="3.5" stroke-linecap="round"/>
            </svg>
            
        </div>
        <div class="visit-bubble">
            <p class="visit-tips-title">Before you come</p>
            <ul>
                <li><i class="bi bi-check-circle-fill" aria-hidden="true"></i><span>A valid ID.</span></li>
                <li><i class="bi bi-check-circle-fill" aria-hidden="true"></i><span>Any medical records, and X-ray or MRI results if you have them.</span></li>
                <li><i class="bi bi-check-circle-fill" aria-hidden="true"></i><span>A list of your current medications and any allergies.</span></li>
                <li><i class="bi bi-check-circle-fill" aria-hidden="true"></i><span>Comfortable clothes you can move in.</span></li>
            </ul>
        </div>
    </div>
</section>
