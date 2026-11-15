@extends('layouts.admin')

@section('title', 'Replay · '.$patient['name'])

@section('content')
    @php
        $tz = config('app.timezone');
        $eventLabels = ['counted' => 'Rep counted', 'rejected' => 'Rep not counted', 'hold' => 'Hold'];
        // What the player needs (session-replay.js). @json escapes <, >, & and quotes, so a note can't close the tag.
        $payload = $replay ? array_intersect_key($replay, array_flip(['chunks', 'aspect', 'mirrored', 'fps', 'angleLabel', 'events'])) : null;
        $clock = fn (int $ms) => intdiv(intdiv($ms, 1000), 60).':'.str_pad((string) (intdiv($ms, 1000) % 60), 2, '0', STR_PAD_LEFT);
    @endphp

    <div class="mb-3">
        <a href="{{ route('patients.show', $patient['uid']) }}" class="back-link text-decoration-none small"><i class="bi bi-arrow-left me-1"></i>{{ $patient['name'] }}</a>
    </div>

    <div class="mb-4">
        <p class="page-title mb-1">Movement replay</p>
        <p class="page-subtitle mb-0">{{ $session['exerciseName'] }} · {{ $session['startTime']?->setTimezone($tz)->format('M j, Y, g:i A') ?? 'Date unknown' }}</p>
    </div>

    <div class="row g-4">
        <div class="col-lg-8">
            <div class="card shadow-sm border-0">
                <div class="card-body">
                    @if ($replay)
                        {{-- tabindex: the player takes Space / arrow keys when focused (session-replay.js). --}}
                        <div class="replay-player" data-replay tabindex="0" aria-label="Movement replay. Space plays or pauses, the arrow keys step one frame.">
                            {{-- Data, not code: type="application/json" never runs. The nonce is only there because the CSP check expects one on every script tag. --}}
                            <script type="application/json" data-replay-data nonce="{{ Vite::cspNonce() }}">@json($payload)</script>
                            <div class="replay-stage">
                                <canvas class="replay-canvas" role="img" aria-label="Stick figure of the patient's movement"></canvas>
                                <div class="replay-out-of-frame" data-replay-out-of-frame hidden>Out of frame</div>
                                <div class="replay-caption" data-replay-caption aria-live="polite"></div>
                            </div>
                            <div class="replay-controls" data-replay-controls></div>
                            <p class="replay-error text-danger small mt-2 mb-0" data-replay-error hidden>The replay could not be played in this browser.</p>
                            <noscript><p class="small mt-2 mb-0">Turn on JavaScript to play the replay.</p></noscript>

                            <p class="replay-note small mt-3 mb-0">
                                <i class="bi bi-info-circle me-1"></i>This is the body-tracking data the app used, not a video. Points the camera could not see are left out.
                                @if ($replay['truncated'])
                                    Only the first 10 minutes were saved.
                                @endif
                                @if ($replay['partial'])
                                    Part of this replay could not be loaded, so it stops early.
                                @endif
                            </p>

                            <h6 class="mt-4 mb-2">Events</h6>
                            @if ($replay['events'])
                                <ul class="replay-events list-unstyled mb-0">
                                    @foreach ($replay['events'] as $event)
                                        <li>
                                            <button type="button" class="replay-event replay-event--{{ $event['kind'] }}" data-replay-seek="{{ $event['t'] }}">
                                                <span class="replay-event-time">{{ $clock($event['t']) }}</span>
                                                <span class="replay-event-dot" aria-hidden="true"></span>
                                                <span>{{ $eventLabels[$event['kind']] }}@if ($event['note'] !== ''): <span class="replay-event-note">{{ $event['note'] }}</span>@endif</span>
                                            </button>
                                        </li>
                                    @endforeach
                                </ul>
                            @else
                                <p class="text-muted small mb-0">No reps or holds were recorded in this replay.</p>
                            @endif
                        </div>
                    @else
                        <div class="replay-empty text-center py-5">
                            <i class="bi bi-person-video2 d-block mb-2"></i>
                            <p class="fw-semibold mb-1">No replay available for this session</p>
                            <p class="text-muted small mb-0">The patient may have turned replays off, or it didn't upload. The session's results are still on the right.</p>
                        </div>
                    @endif
                </div>
            </div>
        </div>

        <div class="col-lg-4">
            <div class="card shadow-sm border-0">
                <div class="card-header"><h5 class="mb-0">Session</h5></div>
                <div class="card-body">
                    <dl class="replay-summary mb-0">
                        <dt>Exercise</dt><dd>{{ $session['exerciseName'] }}</dd>
                        <dt>When</dt><dd>{{ $session['startTime']?->setTimezone($tz)->format('M j, Y, g:i A') ?? '—' }}</dd>
                        <dt>Reps counted</dt><dd>{{ $session['completedReps'] }} of {{ $session['targetReps'] }}</dd>
                        <dt>Rejected</dt><dd>{{ $session['rejectedReps'] }}</dd>
                        <dt>Accuracy</dt><dd>{{ $session['accuracy'] === null ? '—' : $session['accuracy'].'%' }}</dd>
                        <dt>Pain</dt><dd>{{ $session['painLevel'] === null ? '—' : $session['painLevel'].'/10' }}
                            @if ($session['painNote'])<div class="text-muted small" style="white-space: pre-wrap;">“{{ $session['painNote'] }}”</div>@endif
                        </dd>
                        <dt>Ended early</dt><dd>{{ $session['endedEarly'] ? 'Yes' : 'No' }}</dd>
                    </dl>
                </div>
            </div>
        </div>
    </div>
@endsection

@if ($replay)
    @push('outside-page')
        @vite('resources/js/session-replay.js')
    @endpush
@endif
