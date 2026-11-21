{{-- Patient messages on the left, staff replies on the right, each labelled with the sender.
     Staff replies get read receipts: one tick = sent, two ticks = the patient has seen it.
     Each bubble may carry a reply quote, an "Edited" label, the unsent placeholder or a
     shared-session card (all coerced by MessagePresenter), and a "⋮" menu with only the
     actions MessagePresenter::withActions() allows (the server checks them again).
     The pinned banner is part of this list so the page's poll refreshes it too. --}}
@include('messages._pinned', ['pinned' => $pinned ?? null, 'patientUid' => $patientUid])
@forelse ($messages as $m)
    @php
        $actions = $m['actions'] ?? [];
        $canEdit = in_array('edit', $actions, true);
        $status = $m['unsent'] ? null : ($m['status'] ?? null); // no ticks on an unsent message
    @endphp
    <div class="d-flex flex-column mb-2 chat-row {{ $m['fromPatient'] ? 'align-items-start' : 'align-items-end' }}"
         id="msg-{{ $m['id'] }}" data-chat-row data-message-id="{{ $m['id'] }}"
         data-sender="{{ $m['senderName'] }}" data-text="{{ $m['text'] }}"
         @if ($canEdit) data-edit-url="{{ route('messages.edit', [$patientUid, $m['id']]) }}" data-edit-until="{{ $m['editUntil']->getTimestampMs() }}" @endif>
        <div class="chat-sender">{{ $m['senderName'] }}</div>
        <div class="chat-line {{ $m['fromPatient'] ? '' : 'chat-line-staff' }}">
            <div class="chat-bubble {{ $m['fromPatient'] ? 'chat-bubble-patient' : 'chat-bubble-staff' }} {{ $m['session'] ? 'chat-bubble-session' : '' }}">
                @if ($m['replyTo'])
                    <button type="button" class="chat-quote" data-chat-scroll-to="{{ $m['replyTo']['id'] }}" title="Show the original message">
                        <span class="chat-quote-sender">{{ $m['replyTo']['senderName'] }}</span>
                        <span class="chat-quote-text">{{ $m['replyTo']['text'] }}</span>
                    </button>
                @endif

                @if ($m['unsent'])
                    <div class="chat-text chat-unsent">{{ $m['mine'] ? 'You deleted a message' : 'Message deleted' }}</div>
                @elseif ($m['session'])
                    @include('messages._session_card', ['session' => $m['session']])
                @else
                    <div class="chat-text">{{ $m['text'] }}</div>
                @endif

                <div class="chat-time">
                    {{ $m['sentAt']?->setTimezone(config('app.timezone'))->format('M j, g:i A') }}
                    @if ($m['editedAt'])
                        <span class="chat-edited">· Edited</span>
                    @endif
                    @if ($status === 'seen')
                        <i class="bi bi-check2-all chat-tick chat-tick-seen" title="Seen" aria-label="Seen"></i>
                    @elseif ($status === 'sent')
                        <i class="bi bi-check2 chat-tick" title="Sent" aria-label="Sent"></i>
                    @endif
                </div>
            </div>

            @if ($actions !== [])
                @include('messages._message_menu', ['m' => $m, 'actions' => $actions, 'patientUid' => $patientUid])
            @endif
        </div>
    </div>
@empty
    <div class="text-center text-muted py-5">No messages yet. Send the first one below.</div>
@endforelse
