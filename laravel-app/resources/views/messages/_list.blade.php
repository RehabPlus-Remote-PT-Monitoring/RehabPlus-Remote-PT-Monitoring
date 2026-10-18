{{-- Patient messages on the left, staff replies on the right, each labelled with the sender. --}}
@forelse ($messages as $m)
    <div class="d-flex flex-column mb-2 {{ $m['fromPatient'] ? 'align-items-start' : 'align-items-end' }}">
        <div class="chat-sender">{{ $m['senderName'] }}</div>
        <div class="chat-bubble {{ $m['fromPatient'] ? 'chat-bubble-patient' : 'chat-bubble-staff' }}">{{ $m['text'] }}<div class="chat-time">{{ $m['sentAt']?->setTimezone(config('app.timezone'))->format('M j, g:i A') }}</div></div>
    </div>
@empty
    <div class="text-center text-muted py-5">No messages yet. Send the first one below.</div>
@endforelse
