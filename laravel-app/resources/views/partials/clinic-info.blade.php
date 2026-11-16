{{-- Visit us: schedule, location, email and contact, with today's hours and quick actions. Needs $clinic (config/clinic.php). --}}
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
    .visit-card { background: var(--card, #fff); border: 1px solid var(--border); border-radius: 1rem; padding: 1.25rem; }
    .visit-title { margin: 0 0 1rem; font-size: 1.25rem; font-weight: 700; }
    .visit-grid { display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); }
    .visit-tile { border: 1px solid var(--border); border-radius: .85rem; padding: 1rem; display: flex; flex-direction: column; gap: .6rem; min-width: 0; }
    .visit-tile-head { display: flex; align-items: center; gap: .65rem; }
    .visit-tile-head .label { margin: 0; font-size: .72rem; font-weight: 700; letter-spacing: .07em; text-transform: uppercase; color: var(--muted, #64748b); }
    .visit-icon { display: grid; place-items: center; width: 40px; height: 40px; border-radius: 50%; background: var(--primary-light, #ccfbf1); color: var(--primary-dark, #0f766e); font-size: 1.1rem; flex-shrink: 0; }
    .visit-value { margin: 0; font-weight: 600; line-height: 1.4; overflow-wrap: anywhere; color: var(--text, #0f172a); }
    .visit-status { align-self: flex-start; display: inline-flex; align-items: center; gap: .45rem; padding: .3rem .75rem; border-radius: 999px; font-size: .85rem; font-weight: 600; }
    .visit-status::before { content: ''; width: .55rem; height: .55rem; border-radius: 50%; background: currentColor; }
    .visit-status-open { background: #dcfce7; color: #166534; }
    .visit-status-closed { background: #f1f5f9; color: #475569; }
    .visit-list { list-style: none; margin: 0; padding: 0; display: grid; gap: .35rem; }
    .visit-list li { display: flex; align-items: center; flex-wrap: wrap; gap: .4rem; padding: .35rem .5rem; border-radius: .5rem; font-size: .92rem; }
    .visit-list li.is-today { background: var(--primary-light, #ccfbf1); }
    .visit-list .hours { color: var(--muted, #64748b); }
    .visit-list .visit-status { flex-basis: 100%; margin-top: .15rem; font-size: .8rem; padding: .2rem .6rem; }
    .visit-today { margin-left: auto; font-size: .72rem; font-weight: 700; text-transform: uppercase; letter-spacing: .05em; color: var(--primary-dark, #0f766e); }
    /* Buttons sit at the bottom of each tile and share one size, so the row lines up across tiles. */
    .visit-actions { margin-top: auto; padding-top: .25rem; display: flex; }
    .visit-actions .btn { width: 100%; font-size: .85rem; }
    @media (prefers-reduced-motion: no-preference) { .visit-tile { transition: box-shadow .2s ease; } .visit-tile:hover { box-shadow: 0 6px 18px rgba(15, 23, 42, .08); } }
</style>

<section class="visit-card shadow-sm mb-4" aria-labelledby="visit-heading" data-visit>
    <h2 class="visit-title" id="visit-heading">Visit us</h2>

    <div class="visit-grid">
        {{-- Schedule: the open/closed status for today, and today's row highlighted --}}
        <article class="visit-tile">
            <div class="visit-tile-head">
                <span class="visit-icon"><i class="bi bi-clock" aria-hidden="true"></i></span>
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
                            {{-- Today's status sits on today's own row --}}
                            <span class="visit-status {{ $isOpen ? 'visit-status-open' : 'visit-status-closed' }}" data-visit-status="{{ $isOpen ? 'open' : 'closed' }}">{{ $status }}</span>
                        @endif
                    </li>
                @endforeach
            </ul>
            @if ($todaySlot === null)
                {{-- No hours today: the status goes under the list --}}
                <span class="visit-status visit-status-closed" data-visit-status="closed">{{ $status }}</span>
            @endif
        </article>

        {{-- Location --}}
        <article class="visit-tile">
            <div class="visit-tile-head">
                <span class="visit-icon"><i class="bi bi-geo-alt" aria-hidden="true"></i></span>
                <p class="label">Location</p>
            </div>
            <p class="visit-value">{{ $clinic['location'] }}</p>
            <div class="visit-actions">
                <a href="{{ $clinic['map_url'] }}" target="_blank" rel="noopener noreferrer" class="btn btn-sm btn-primary"><i class="bi bi-signpost-2 me-1" aria-hidden="true"></i>Get directions</a>
            </div>
        </article>

        {{-- Email --}}
        <article class="visit-tile">
            <div class="visit-tile-head">
                <span class="visit-icon"><i class="bi bi-envelope" aria-hidden="true"></i></span>
                <p class="label">Email</p>
            </div>
            <p class="visit-value">{{ $clinic['email'] }}</p>
            <div class="visit-actions">
                <a href="{{ $mailLink }}" class="btn btn-sm btn-outline-primary" target="_blank" rel="noopener noreferrer"><i class="bi bi-send me-1" aria-hidden="true"></i>Send an email</a>
            </div>
        </article>

        {{-- Contact: the number only, no button --}}
        <article class="visit-tile">
            <div class="visit-tile-head">
                <span class="visit-icon"><i class="bi bi-telephone" aria-hidden="true"></i></span>
                <p class="label">Contact</p>
            </div>
            <p class="visit-value">{{ $clinic['phone'] }}</p>
        </article>
    </div>
</section>
