{{-- A bubble's actions, opened by resources/js/chat-actions.js: a Reply button next to the
     bubble and, beyond it, the "⋯" menu (Copy, Pin/Unpin, Edit, Unsend; same order as the app). Staff bubbles are
     on the right, so the CSS mirrors the order there: "⋯", Reply, bubble.
     Reply, Edit and Copy happen in the page; Pin, Unpin and Unsend are small forms (Unsend
     asks first through data-confirm). --}}
@php
    $menuItems = array_values(array_diff($actions, ['reply']));
@endphp
<div class="chat-actions">
    @if (in_array('reply', $actions, true))
        <button type="button" class="chat-action-btn" data-chat-reply aria-label="Reply" title="Reply">
            <i class="bi bi-reply" aria-hidden="true"></i>
        </button>
    @endif
    @if ($menuItems !== [])
        <button type="button" class="chat-action-btn chat-menu-toggle" data-chat-menu-toggle aria-haspopup="menu" aria-expanded="false" aria-label="More actions" title="More">
            <i class="bi bi-three-dots" aria-hidden="true"></i>
        </button>
        <div class="chat-menu" role="menu" data-chat-menu hidden>
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
            @if (in_array('edit', $actions, true))
                <button type="button" role="menuitem" data-chat-edit><i class="bi bi-pencil" aria-hidden="true"></i>Edit</button>
            @endif
            @if (in_array('unsend', $actions, true))
                <form method="POST" action="{{ route('messages.unsend', [$patientUid, $m['id']]) }}"
                      data-confirm="Unsend this message? The patient will see “Message deleted” instead of it." data-confirm-danger>
                    @csrf
                    <button type="submit" role="menuitem" class="chat-menu-danger" data-chat-unsend><i class="bi bi-trash3" aria-hidden="true"></i>Unsend</button>
                </form>
            @endif
        </div>
    @endif
</div>
