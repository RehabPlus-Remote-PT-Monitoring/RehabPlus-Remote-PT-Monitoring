@forelse ($messages as $m)
    <div class="d-flex mb-2 {{ $m['fromPatient'] ? 'justify-content-start' : 'justify-content-end' }}">
        <div class="chat-bubble {{ $m['fromPatient'] ? 'chat-bubble-patient' : 'chat-bubble-staff' }}">{{ $m['text'] }}<div class="chat-time">{{ $m['sentAt']?->setTimezone(config('app.timezone'))->format('M j, g:i A') }}</div></div>
    </div>
@empty
    <div class="text-center text-muted py-5">No messages yet. Send the first one below.</div>
@endforelse
