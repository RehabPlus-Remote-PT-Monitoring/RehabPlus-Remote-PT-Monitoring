{{-- The conversation's pinned message (one per thread, shared with the patient app).
     Clicking it scrolls to the message when it is loaded on the page. --}}
@if ($pinned)
    <div class="chat-pinned" data-chat-pinned>
        <i class="bi bi-pin-angle-fill chat-pinned-icon" aria-hidden="true"></i>
        <button type="button" class="chat-pinned-body" data-chat-scroll-to="{{ $pinned['id'] }}"
                title="{{ $pinned['onPage'] ? 'Show the pinned message' : 'The pinned message is older than the messages shown here' }}">
            <span class="chat-pinned-label">Pinned{{ $pinned['senderName'] ? ' · '.$pinned['senderName'] : '' }}</span>
            <span class="chat-pinned-text">{{ $pinned['text'] }}</span>
        </button>
        <form method="POST" action="{{ route('messages.unpin', $patientUid) }}" class="chat-pinned-unpin">
            @csrf
            <button type="submit" class="btn btn-sm btn-outline-secondary">Unpin</button>
        </form>
    </div>
@endif
