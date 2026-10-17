@forelse ($messages as $m)
    <div class="d-flex mb-2 {{ $m['fromPatient'] ? 'justify-content-start' : 'justify-content-end' }}">
        <div class="px-3 py-2 rounded-4 {{ $m['fromPatient'] ? 'bg-body-secondary' : 'bg-primary text-white' }}" style="max-width: 70%; white-space: pre-wrap;">{{ $m['text'] }}<div class="small mt-1 {{ $m['fromPatient'] ? 'text-muted' : 'text-white-50' }}">{{ $m['sentAt']?->setTimezone(config('app.timezone'))->format('M j, g:i A') }}</div></div>
    </div>
@empty
    <div class="text-center text-muted py-5">No messages yet. Send the first one below.</div>
@endforelse
