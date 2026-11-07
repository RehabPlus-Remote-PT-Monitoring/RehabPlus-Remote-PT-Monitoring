@extends('layouts.admin')

@section('title', 'Messages')

@section('content')
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
        <div class="card shadow-sm border-0">
            <div class="list-group list-group-flush">
                @forelse ($conversations as $c)
                    <a href="{{ route('messages.show', $c['patientUid']) }}"
                       class="list-group-item list-group-item-action d-flex align-items-center gap-3 py-3 {{ $c['unread'] ? 'fw-semibold' : '' }}">
                        <div class="user-avatar flex-shrink-0">{{ strtoupper(mb_substr($c['patientName'], 0, 1)) }}</div>
                        <div class="flex-grow-1 min-w-0">
                            <div class="d-flex justify-content-between">
                                <span>{{ $c['patientName'] }}</span>
                                <small class="text-muted">{{ $c['lastMessageAt']?->setTimezone(config('app.timezone'))->diffForHumans() }}</small>
                            </div>
                            <div class="text-muted small text-truncate">
                                @if ($c['lastMessage'])
                                    {{ $c['lastSenderRole'] === 'staff' ? 'You: ' : '' }}{{ $c['lastMessage'] }}
                                @else
                                    No messages yet{{ $c['condition'] ? ' · '.$c['condition'] : '' }}
                                @endif
                            </div>
                        </div>
                        @if ($c['unread'])
                            <span class="badge rounded-pill bg-danger">{{ $c['unread'] }}</span>
                        @endif
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
        </div>
    @endif
@endsection
