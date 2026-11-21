@extends('layouts.admin')

@section('title', 'Messages · '.$partner['name'])

@section('content')
    @php($tagStyle = $partner['role'] === 'admin' ? 'bg-danger-subtle text-danger' : 'bg-info-subtle text-info')
    <div class="mb-3">
        <a href="{{ route('messages.index') }}" class="back-link text-decoration-none small"><i class="bi bi-arrow-left me-1"></i>All conversations</a>
        <p class="page-title mb-0 mt-1 d-flex align-items-center gap-2">
            {{ $partner['name'] }}
            <span class="badge rounded-pill {{ $tagStyle }} fs-6 fw-normal">{{ \App\Auth\StaffUser::ROLE_LABELS[$partner['role']] ?? ucfirst($partner['role']) }}</span>
        </p>
    </div>

    @include('partials.flash')

    <div class="card shadow-sm border-0">
        <div class="card-body" style="height: 55vh; overflow-y: auto;" id="staffChatList">
            @forelse ($messages as $m)
                <div class="d-flex flex-column mb-2 {{ $m['fromMe'] ? 'align-items-end' : 'align-items-start' }}">
                    <div class="chat-sender">{{ $m['senderName'] }}</div>
                    <div class="chat-bubble {{ $m['fromMe'] ? 'chat-bubble-staff' : 'chat-bubble-patient' }}">{{ $m['text'] }}<div class="chat-time">{{ $m['sentAt']?->setTimezone(config('app.timezone'))->format('M j, g:i A') }}</div></div>
                </div>
            @empty
                <div class="text-center text-muted py-5">No messages yet. Send the first one below.</div>
            @endforelse
        </div>
        <div class="card-footer bg-transparent">
            <form method="POST" action="{{ route('staff-chat.send', $partner['uid']) }}" class="d-flex gap-2 align-items-end">
                @csrf
                <textarea name="text" rows="2" maxlength="{{ $maxLength }}" required
                          class="form-control @error('text') is-invalid @enderror"
                          placeholder="Write a message… (Enter to send, Shift+Enter for a new line)">{{ old('text') }}</textarea>
                <button type="submit" class="btn btn-primary px-4"><i class="bi bi-send-fill me-1"></i>Send</button>
            </form>
            @error('text')
                <div class="text-danger small mt-1">{{ $message }}</div>
            @enderror
        </div>
    </div>

    <script nonce="{{ Vite::cspNonce() }}">
        (() => {
            const list = document.getElementById('staffChatList');
            list.scrollTop = list.scrollHeight;

            // Enter sends, Shift+Enter adds a line.
            const form = list.closest('.card').querySelector('form');
            const box = form.querySelector('textarea');
            box.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    if (box.value.trim()) form.requestSubmit();
                }
            });
        })();
    </script>
@endsection
