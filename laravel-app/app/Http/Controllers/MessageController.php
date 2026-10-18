<?php

namespace App\Http\Controllers;

use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\GoogleAccessToken;
use App\Services\Messaging\MessagingService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

/**
 * Staff inbox for messages from the patient app. Which conversation a user
 * answers comes from their role (see MessagingService), so it isn't in the URL.
 */
class MessageController extends Controller
{
    public function __construct(private MessagingService $messaging)
    {
    }

    public function index(Request $request): View
    {
        $data = ['thread' => $this->messaging->threadFor($request->user()), 'conversations' => [], 'error' => null];

        if (! GoogleAccessToken::isConfigured()) {
            $data['error'] = 'Messaging is not set up on this server yet: FIREBASE_CREDENTIALS is missing from .env.';

            return view('messages.index', $data);
        }

        try {
            $data = $this->messaging->inbox($request->user()) + $data;
        } catch (FirebaseException $e) {
            report($e);
            $data['error'] = 'Could not load conversations from Firebase. Try again in a moment.';
        }

        return view('messages.index', $data);
    }

    public function show(Request $request, string $patientUid): View
    {
        [$thread, $patient] = $this->authorizeThread($request, $patientUid);

        return view('messages.show', [
            'thread' => $thread,
            'patient' => $patient,
            'patientUid' => $patientUid,
            'messages' => $this->loadAndMarkRead($patientUid, $thread),
            'maxLength' => MessagingService::MAX_LENGTH,
        ]);
    }

    /** Just the message list, polled by the conversation page for new messages. */
    public function feed(Request $request, string $patientUid): View
    {
        [$thread] = $this->authorizeThread($request, $patientUid);

        return view('messages._list', ['messages' => $this->loadAndMarkRead($patientUid, $thread)]);
    }

    public function reply(Request $request, string $patientUid): RedirectResponse
    {
        $validated = $request->validate([
            'text' => ['required', 'string', 'max:'.MessagingService::MAX_LENGTH],
        ]);

        [$thread, $patient] = $this->authorizeThread($request, $patientUid);

        try {
            $phones = $this->messaging->reply($request->user(), $patientUid, $patient, $thread, $validated['text']);
        } catch (FirebaseException $e) {
            report($e);

            return back()->withInput()->with('error', 'Message not sent. '.$e->getMessage());
        }

        return redirect()->route('messages.show', $patientUid)->with(
            'success',
            match (true) {
                $phones === null => 'Message sent. The patient turned off message alerts, so they will see it next time they open the app.',
                $phones > 0 => 'Message sent.',
                default => 'Message sent. The patient will see it next time they open the app (no phone is registered for notifications).',
            },
        );
    }

    private function loadAndMarkRead(string $patientUid, string $thread): array
    {
        try {
            $messages = $this->messaging->messages($patientUid, $thread);
        } catch (FirebaseException $e) {
            report($e);
            abort(503, 'Could not reach Firebase. Try again in a moment.');
        }

        try {
            $this->messaging->markRead($patientUid, $thread);
        } catch (FirebaseException $e) {
            report($e); // the badge stays; not worth failing the page over
        }

        return $messages;
    }

    /** @return array{0: string, 1: array} thread id and patient profile; 404s otherwise */
    private function authorizeThread(Request $request, string $patientUid): array
    {
        $thread = $this->messaging->threadFor($request->user());

        try {
            $patient = $thread ? $this->messaging->authorize($request->user(), $patientUid, $thread) : null;
        } catch (FirebaseException $e) {
            report($e);
            abort(503, 'Could not reach Firebase. Try again in a moment.');
        }

        // 404 rather than 403, so staff can't probe which patient ids exist.
        abort_unless($patient, 404);

        return [$thread, $patient];
    }
}
