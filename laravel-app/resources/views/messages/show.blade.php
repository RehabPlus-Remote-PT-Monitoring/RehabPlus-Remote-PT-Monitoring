@extends('layouts.admin')

@section('title', 'Messages · '.($patient['name'] ?? 'Patient'))

@section('content')
    <div class="d-flex justify-content-between align-items-center mb-3">
        <div>
            <a href="{{ route('messages.index') }}" class="text-decoration-none small"><i class="bi bi-arrow-left me-1"></i>All conversations</a>
            <p class="page-title mb-0 mt-1">{{ $patient['name'] ?? 'Unnamed patient' }}</p>
            <p class="page-subtitle mb-0">
                {{ $thread === 'therapist' ? 'Therapist conversation' : 'Clinic conversation' }}{{ ! empty($patient['condition']) ? ' · '.$patient['condition'] : '' }}
            </p>
        </div>
    </div>

    @if (session('success'))
        <div class="alert alert-success">{{ session('success') }}</div>
    @endif
    @if (session('error'))
        <div class="alert alert-danger">{{ session('error') }}</div>
    @endif

    <div class="card shadow-sm border-0">
        <div class="card-body" id="messageList" style="height: 55vh; overflow-y: auto;"
             data-feed-url="{{ route('messages.feed', $patientUid) }}">
            @include('messages._list', ['messages' => $messages])
        </div>
        <div class="card-footer bg-transparent">
            <form method="POST" action="{{ route('messages.reply', $patientUid) }}" class="d-flex gap-2 align-items-end">
                @csrf
                <textarea name="text" rows="2" maxlength="{{ $maxLength }}" required
                          class="form-control @error('text') is-invalid @enderror"
                          placeholder="Write a reply… (Enter to send, Shift+Enter for a new line)">{{ old('text') }}</textarea>
                <button type="submit" class="btn btn-primary px-4"><i class="bi bi-send-fill me-1"></i>Send</button>
            </form>
            @error('text')
                <div class="text-danger small mt-1">{{ $message }}</div>
            @enderror
        </div>
    </div>

    <script nonce="{{ Vite::cspNonce() }}">
        (() => {
            const list = document.getElementById('messageList');
            const form = list.closest('.card').querySelector('form');
            const box = form.querySelector('textarea');
            const toBottom = () => { list.scrollTop = list.scrollHeight; };
            toBottom();

            // Enter sends, Shift+Enter adds a line.
            box.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    if (box.value.trim()) form.requestSubmit();
                }
            });

            // Pull new patient messages every 10s; only scroll if already at the bottom.
            setInterval(async () => {
                if (document.hidden) return;
                try {
                    const res = await fetch(list.dataset.feedUrl, { headers: { 'X-Requested-With': 'XMLHttpRequest' } });
                    if (!res.ok) return;
                    const html = await res.text();
                    if (html === list.innerHTML) return;
                    const atBottom = list.scrollHeight - list.scrollTop - list.clientHeight < 40;
                    list.innerHTML = html;
                    if (atBottom) toBottom();
                } catch (_) { /* offline; try again next tick */ }
            }, 10000);
        })();
    </script>
@endsection
