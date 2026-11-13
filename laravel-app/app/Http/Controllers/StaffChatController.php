<?php

namespace App\Http\Controllers;

use App\Services\Firebase\FirebaseException;
use App\Services\Messaging\MessagingService;
use App\Services\StaffChat\StaffChatService;
use Illuminate\Support\Facades\Cache;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

/** Messages between administrators and physical therapists. */
class StaffChatController extends Controller
{
    public function __construct(private StaffChatService $chats)
    {
    }

    public function show(Request $request, string $uid): View
    {
        $partner = $this->partnerOr404($request, $uid);

        try {
            $messages = $this->chats->messages($request->user(), $uid);
            $this->chats->markRead($request->user(), $uid);
        } catch (FirebaseException $e) {
            report($e);
            abort(503, 'Could not reach Firebase. Try again in a moment.');
        }

        // The Messages tab badge is cached; drop it so the opened chat is no longer counted.
        Cache::forget('messages-unread:'.$request->user()->id);

        return view('staff-chat.show', [
            'partner' => $partner,
            'messages' => $messages,
            'maxLength' => MessagingService::MAX_LENGTH,
        ]);
    }

    public function send(Request $request, string $uid): RedirectResponse
    {
        $this->partnerOr404($request, $uid);

        $validated = $request->validate([
            'text' => ['required', 'string', 'max:'.MessagingService::MAX_LENGTH],
        ]);

        try {
            $this->chats->send($request->user(), $uid, $validated['text']);
        } catch (FirebaseException $e) {
            report($e);

            return back()->withInput()->with('error', 'Message not sent. Try again in a moment.');
        }

        return redirect()->route('staff-chat.show', $uid);
    }

    /** @return array<string, mixed> */
    private function partnerOr404(Request $request, string $uid): array
    {
        try {
            $partner = $this->chats->partner($request->user(), $uid);
        } catch (FirebaseException $e) {
            report($e);
            abort(503, 'Could not reach Firebase. Try again in a moment.');
        }

        abort_if($partner === null, 404);

        return $partner;
    }
}
