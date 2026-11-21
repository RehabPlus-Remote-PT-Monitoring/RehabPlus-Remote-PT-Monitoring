@extends('layouts.admin')

@section('title', 'Messages · '.($patient['name'] ?? 'Patient'))

@section('content')
    @php($archived = ! empty($patient['archived']))
    <div class="d-flex justify-content-between align-items-center mb-3">
        <div>
            <a href="{{ route('messages.index', $archived ? ['archived' => 1] : []) }}" class="back-link text-decoration-none small"><i class="bi bi-arrow-left me-1"></i>All conversations</a>
            <p class="page-title mb-0 mt-1 d-flex align-items-center gap-2">
                {{ $patient['name'] ?? 'Unnamed patient' }}
                <span class="badge rounded-pill bg-success-subtle text-success fs-6 fw-normal">Patient</span>
            </p>
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
             data-feed-url="{{ route('messages.feed', $patientUid) }}"
             data-status-url="{{ route('messages.status', $patientUid) }}"
             data-version="{{ $version }}">
            @include('messages._list', ['messages' => $messages, 'pinned' => $pinned, 'patientUid' => $patientUid])
        </div>
        <div class="card-footer bg-transparent">
            @if ($archived)
                <p class="small text-muted mb-0" data-archived-note>
                    <i class="bi bi-archive me-1"></i>This patient is archived. Restore them from <a href="{{ route('patients.index', ['archived' => 1]) }}">Archived Patients</a> to send a message.
                </p>
            @else
                {{-- "Reply" in a bubble's menu fills this in (resources/js/chat-actions.js). --}}
                <div class="chat-reply-preview" data-reply-preview hidden>
                    <i class="bi bi-reply chat-reply-preview-icon" aria-hidden="true"></i>
                    <div class="chat-reply-preview-body">
                        <span class="chat-reply-preview-label">Replying to <span data-reply-preview-sender></span></span>
                        <span class="chat-reply-preview-text" data-reply-preview-text></span>
                    </div>
                    <button type="button" class="btn-close" data-reply-cancel aria-label="Cancel reply"></button>
                </div>
                <form method="POST" action="{{ route('messages.reply', $patientUid) }}" class="d-flex gap-2 align-items-end" data-chat-composer>
                    @csrf
                    <input type="hidden" name="reply_to_id" value="{{ old('reply_to_id') }}" data-reply-to-id>
                    <textarea name="text" rows="2" maxlength="{{ $maxLength }}" required
                              class="form-control @error('text') is-invalid @enderror"
                              placeholder="Write a reply… (Enter to send, Shift+Enter for a new line)">{{ old('text') }}</textarea>
                    <button type="submit" class="btn btn-primary px-4"><i class="bi bi-send-fill me-1"></i>Send</button>
                </form>
                @error('text')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            @endif
        </div>
    </div>

    <script nonce="{{ Vite::cspNonce() }}">
        (() => {
            const list = document.getElementById('messageList');
            const form = list.closest('.card').querySelector('form');
            const box = form?.querySelector('textarea'); // no form for an archived patient
            const toBottom = () => { list.scrollTop = list.scrollHeight; };
            toBottom();

            // Enter sends, Shift+Enter adds a line.
            box?.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    if (box.value.trim()) form.requestSubmit();
                }
            });

            // Every 1.5s ask for the thread's version (one cheap summary read);
            // only when it changed (new message, or the patient read the chat)
            // reload the messages. Only scroll if already at the bottom.
            const headers = { 'X-Requested-With': 'XMLHttpRequest' };
            let version = list.dataset.version;
            let busy = false;
            const refresh = async () => {
                const res = await fetch(list.dataset.feedUrl, { headers });
                if (!res.ok) return;
                const html = await res.text();
                version = res.headers.get('X-Thread-Version') || version;
                if (html === list.innerHTML) return;
                const atBottom = list.scrollHeight - list.scrollTop - list.clientHeight < 40;
                list.innerHTML = html;
                if (atBottom) toBottom();
            };
            setInterval(async () => {
                // Reloading the list would close a bubble menu someone has open,
                // or remove the Unsend form its "Do you want to proceed?" pop-up submits.
                if (document.hidden || busy || list.querySelector('[data-chat-menu]:not([hidden])') || document.querySelector('dialog[open]')) return;
                busy = true; // a slow request mustn't stack up behind the next tick
                try {
                    const res = await fetch(list.dataset.statusUrl, { headers });
                    if (res.ok && (await res.json()).version !== version) await refresh();
                } catch (_) { /* offline; try again next tick */ }
                finally { busy = false; }
            }, 1500);
        })();
    </script>
@endsection
