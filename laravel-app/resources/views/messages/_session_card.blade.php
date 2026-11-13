{{-- Compact card for a session the patient shared from the app (MessagePresenter::session()).
     A box is left out when its value is missing; accuracy is green >= 80, amber 50-79, red < 50. --}}
<div class="chat-session" data-chat-session>
    <div class="chat-session-head">
        <i class="bi bi-activity chat-session-icon" aria-hidden="true"></i>
        <div class="min-w-0">
            <div class="chat-session-title">{{ $session['exerciseName'] }}</div>
            <div class="chat-session-sub">Shared session{{ $session['startTime'] ? ' · '.$session['startTime']->setTimezone(config('app.timezone'))->format('M j, g:i A') : '' }}</div>
        </div>
    </div>

    @if ($session['completedReps'] !== null || $session['accuracy'] !== null || $session['painLevel'] !== null)
        <div class="chat-session-stats">
            @if ($session['completedReps'] !== null)
                <div class="chat-session-stat" data-stat="reps">
                    <span class="chat-session-value">{{ $session['completedReps'] }}{{ $session['targetReps'] !== null ? '/'.$session['targetReps'] : '' }}</span>
                    <span class="chat-session-label">Reps</span>
                </div>
            @endif
            @if ($session['accuracy'] !== null)
                <div class="chat-session-stat chat-tone-{{ $session['accuracyTone'] }}" data-stat="accuracy">
                    <span class="chat-session-value">{{ $session['accuracy'] }}%</span>
                    <span class="chat-session-label">Accuracy</span>
                </div>
            @endif
            @if ($session['painLevel'] !== null)
                <div class="chat-session-stat chat-tone-fair" data-stat="pain">
                    <span class="chat-session-value">{{ $session['painLevel'] }}/10</span>
                    <span class="chat-session-label">Pain</span>
                </div>
            @endif
        </div>
    @endif

    @if ($session['painNote'])
        <div class="chat-session-note">“{{ $session['painNote'] }}”</div>
    @endif
</div>
