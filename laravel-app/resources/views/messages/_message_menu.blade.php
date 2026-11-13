{{-- A bubble's "⋮" menu, opened by resources/js/chat-actions.js. Reply, Edit and Copy
     happen in the page; Pin, Unpin and Unsend are small forms (Unsend asks
     "Do you want to proceed?" through data-confirm first). --}}
<div class="chat-actions">
    <button type="button" class="chat-menu-toggle" data-chat-menu-toggle aria-haspopup="menu" aria-expanded="false" aria-label="Message actions">
        <i class="bi bi-three-dots-vertical" aria-hidden="true"></i>
    </button>
    <div class="chat-menu" role="menu" data-chat-menu hidden>
        @if (in_array('reply', $actions, true))
            <button type="button" role="menuitem" data-chat-reply><i class="bi bi-reply" aria-hidden="true"></i>Reply</button>
        @endif
        @if (in_array('edit', $actions, true))
            <button type="button" role="menuitem" data-chat-edit><i class="bi bi-pencil" aria-hidden="true"></i>Edit</button>
        @endif
        @if (in_array('copy', $actions, true))
            <button type="button" role="menuitem" data-chat-copy><i class="bi bi-copy" aria-hidden="true"></i>Copy</button>
        @endif
        @if (in_array('pin', $actions, true))
            <form method="POST" action="{{ route('messages.pin', [$patientUid, $m['id']]) }}">
                @csrf
                <button type="submit" role="menuitem" data-chat-pin><i class="bi bi-pin-angle" aria-hidden="true"></i>Pin</button>
            </form>
        @elseif (in_array('unpin', $actions, true))
            <form method="POST" action="{{ route('messages.unpin', $patientUid) }}">
                @csrf
                <button type="submit" role="menuitem" data-chat-unpin><i class="bi bi-pin-angle-fill" aria-hidden="true"></i>Unpin</button>
            </form>
        @endif
        @if (in_array('unsend', $actions, true))
            <form method="POST" action="{{ route('messages.unsend', [$patientUid, $m['id']]) }}"
                  data-confirm="Unsend this message? The patient will see “Message unsent” instead of it." data-confirm-danger>
                @csrf
                <button type="submit" role="menuitem" class="chat-menu-danger" data-chat-unsend><i class="bi bi-trash3" aria-hidden="true"></i>Unsend</button>
            </form>
        @endif
    </div>
</div>
