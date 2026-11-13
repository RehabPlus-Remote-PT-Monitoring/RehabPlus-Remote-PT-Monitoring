@extends('layouts.admin')

@section('title', 'Messages')

@section('content')
    @php($tagStyles = [
        'patient' => 'bg-success-subtle text-success',
        'admin' => 'bg-danger-subtle text-danger',
        'therapist' => 'bg-info-subtle text-info',
    ])

    <div class="d-flex justify-content-between align-items-center mb-4">
        <div>
            <p class="page-title mb-1">Messages</p>
        </div>
        <a href="{{ route('messages.index', $archived ? ['archived' => 1] : []) }}" class="btn btn-outline-secondary"><i class="bi bi-arrow-clockwise me-1"></i>Refresh</a>
    </div>

    <nav class="nav nav-pills gap-2 mb-3" aria-label="Message folders">
        <a href="{{ route('messages.index') }}" class="nav-link {{ $archived ? '' : 'active' }}" @if (! $archived) aria-current="page" @endif>
            <i class="bi bi-inbox me-1"></i>Inbox
        </a>
        <a href="{{ route('messages.index', ['archived' => 1]) }}" class="nav-link {{ $archived ? 'active' : '' }}" @if ($archived) aria-current="page" @endif>
            <i class="bi bi-archive me-1"></i>Archived Messages
        </a>
    </nav>

    @if ($error)
        {{-- Stays: it replaces the conversation list, so the page would be blank without it. --}}
        <div class="alert alert-danger" data-keep>{{ $error }}</div>
    @else
        <div class="input-group mb-3">
            <input id="conversation-search" type="search" class="form-control" placeholder="Search name, role, or message" aria-label="Search conversations">
            {{-- Decorative: the list filters as you type. --}}
            <span class="input-group-text" aria-hidden="true"><i class="bi bi-search"></i></span>
        </div>

        <div class="card shadow-sm border-0">
            <div class="list-group list-group-flush">
                @forelse ($conversations as $c)
                    <a href="{{ $c['url'] }}"
                       class="list-group-item list-group-item-action py-3 {{ $c['unread'] ? 'conversation-unread' : 'conversation-read' }}"
                       data-conversation-row
                       data-search="{{ strtolower($c['name'].' '.$c['tag'].' '.($c['lastMessage'] ?? '')) }}">
                        <div class="d-flex align-items-center gap-3">
                            <div class="user-avatar flex-shrink-0">{{ strtoupper(mb_substr($c['name'], 0, 1)) }}</div>
                            <div class="flex-grow-1 min-w-0">
                                <div class="d-flex justify-content-between align-items-center gap-2">
                                    <span class="d-flex align-items-center gap-2 min-w-0">
                                        <span class="conversation-name text-truncate">{{ $c['name'] }}</span>
                                        <span class="badge rounded-pill {{ $tagStyles[$c['tagTone']] ?? 'bg-light text-dark' }} flex-shrink-0">{{ $c['tag'] }}</span>
                                    </span>
                                    <small class="text-muted flex-shrink-0">{{ $c['lastMessageAt']?->setTimezone(config('app.timezone'))->diffForHumans() }}</small>
                                </div>
                                <div class="conversation-preview small text-truncate">
                                    @if ($c['lastMessage'])
                                        {{ $c['fromMe'] ? 'You: ' : '' }}{{ $c['lastMessage'] }}
                                    @else
                                        No messages yet{{ $c['subtitle'] ? ' · '.$c['subtitle'] : '' }}
                                    @endif
                                </div>
                            </div>
                            @if ($c['unread'])
                                <span class="conversation-new badge rounded-pill flex-shrink-0" aria-label="{{ $c['unread'] }} unread">{{ $c['unread'] }} new</span>
                            @elseif ($c['lastMessage'])
                                <span class="conversation-seen flex-shrink-0" title="Read" aria-label="Read"><i class="bi bi-check2-all"></i> Read</span>
                            @endif
                        </div>
                    </a>
                @empty
                    <div class="text-center text-muted py-5">
                        @if ($archived)
                            No archived conversations.
                        @else
                            {{ $thread === 'therapist' ? 'No patients are assigned to you yet.' : 'No patients yet.' }}
                        @endif
                    </div>
                @endforelse
            </div>
            @if ($conversations !== [])
                <div class="text-center text-muted py-4" data-conversation-search-empty hidden>No conversations match what you typed.</div>
            @endif
        </div>

        <script nonce="{{ Vite::cspNonce() }}">
            (() => {
                // The list filters live as you type, like the patient search.
                const input = document.getElementById('conversation-search');
                const empty = document.querySelector('[data-conversation-search-empty]');
                input?.addEventListener('input', () => {
                    const term = input.value.trim().toLowerCase();
                    let shown = 0;
                    document.querySelectorAll('[data-conversation-row]').forEach((row) => {
                        const match = row.dataset.search.includes(term);
                        row.hidden = !match;
                        shown += match ? 1 : 0;
                    });
                    empty?.toggleAttribute('hidden', shown > 0);
                });
            })();
        </script>
    @endif
@endsection
