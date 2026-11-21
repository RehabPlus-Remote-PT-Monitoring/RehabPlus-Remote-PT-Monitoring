<?php

namespace App\Http\Controllers;

use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirebaseTransport;
use App\Services\Firebase\GoogleAccessToken;
use App\Services\Messaging\ChatActionException;
use App\Services\Messaging\ChatActions;
use App\Services\Messaging\MessagePresenter;
use App\Services\Messaging\MessagingService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Illuminate\View\View;

/**
 * Staff inbox for messages from the patient app. Which conversation a user
 * answers comes from their role (see MessagingService), so it isn't in the URL.
 */
class MessageController extends Controller
{
    public function __construct(private MessagingService $messaging, private ChatActions $actions, private FirebaseTransport $firebase)
    {
    }

    public function index(Request $request): View
    {
        $archived = $request->boolean('archived');
        $data = ['thread' => $this->messaging->threadFor($request->user()), 'conversations' => [], 'error' => null, 'archived' => $archived];

        if (! GoogleAccessToken::isConfigured()) {
            $data['error'] = 'Messaging is not set up on this server yet: FIREBASE_CREDENTIALS is missing from .env.';

            return view('messages.index', $data);
        }

        try {
            $data['conversations'] = $this->messaging->allConversations($request->user(), $archived);
        } catch (FirebaseException $e) {
            report($e);
            $data['error'] = 'Could not load conversations from Firebase. Try again in a moment.';
        }

        return view('messages.index', $data);
    }

    public function show(Request $request, string $patientUid): View
    {
        [$thread, $patient] = $this->authorizeThread($request, $patientUid);

        [$messages, $version, $pinned] = $this->loadAndMarkRead($request, $patientUid, $thread, $patient);

        return view('messages.show', [
            'thread' => $thread,
            'patient' => $patient,
            'patientUid' => $patientUid,
            'messages' => $messages,
            'pinned' => $pinned,
            'version' => $version,
            'maxLength' => MessagingService::MAX_LENGTH,
        ]);
    }

    /**
     * Just the message list, fetched by the conversation page when status()
     * says something changed. The version rides in a header for the next poll.
     */
    public function feed(Request $request, string $patientUid): Response
    {
        [$thread, $patient] = $this->authorizeThread($request, $patientUid);
        [$messages, $version, $pinned] = $this->loadAndMarkRead($request, $patientUid, $thread, $patient);

        return response()->view('messages._list', ['messages' => $messages, 'pinned' => $pinned, 'patientUid' => $patientUid])
            ->header('X-Thread-Version', $version);
    }

    /**
     * Polled every 1.5 s by the conversation page: just the thread's version
     * (one summary read), so new messages and read receipts show up quickly
     * without re-reading every message each time.
     */
    public function status(Request $request, string $patientUid): JsonResponse
    {
        [$thread] = $this->authorizeThread($request, $patientUid);

        try {
            $summary = $this->messaging->summary($patientUid, $thread);
        } catch (FirebaseException $e) {
            report($e);
            abort(503, 'Could not reach Firebase. Try again in a moment.');
        }

        return response()->json(['version' => MessagingService::version($summary)]);
    }

    public function reply(Request $request, string $patientUid): RedirectResponse
    {
        $validated = $request->validate([
            'text' => ['required', 'string', 'max:'.MessagingService::MAX_LENGTH],
            'reply_to_id' => ['nullable', 'string', 'max:128'],
        ]);

        [$thread, $patient] = $this->authorizeThread($request, $patientUid);

        // Archived patients have no app login, so they could never read or answer it.
        if (! empty($patient['archived'])) {
            return redirect()->route('messages.show', $patientUid)
                ->with('error', 'Message not sent. This patient is archived. Restore them to send a message.');
        }

        try {
            // "Reply" in a bubble's menu: quote that message (it must be in this thread).
            $replyTo = empty($validated['reply_to_id'])
                ? null
                : $this->actions->replyTarget($patientUid, $thread, $validated['reply_to_id']);

            $this->messaging->reply($request->user(), $patientUid, $patient, $thread, $validated['text'], $replyTo);
        } catch (ChatActionException $e) {
            Log::info('messages.reply_rejected', ['uid' => $request->user()->id, 'patient' => $patientUid, 'reason' => $e->getMessage()]);

            return back()->withInput()->with('error', 'Message not sent. '.$e->getMessage());
        } catch (FirebaseException $e) {
            report($e);

            return back()->withInput()->with('error', 'Message not sent. '.$e->getMessage());
        }

        // No "Message sent" banner: the new bubble with its tick shows that.
        return redirect()->route('messages.show', $patientUid);
    }

    /** Edit the signed-in staff member's own message (15-minute window). */
    public function edit(Request $request, string $patientUid, string $messageId): RedirectResponse
    {
        $validated = $request->validate([
            'text' => ['required', 'string', 'max:'.MessagingService::MAX_LENGTH],
        ]);
        [$thread] = $this->authorizeThread($request, $patientUid);

        return $this->runAction($patientUid, 'Message not edited.', fn () => $this->actions->edit($request->user(), $patientUid, $thread, $messageId, $validated['text']));
    }

    /** Unsend the signed-in staff member's own message (the page asks "Do you want to proceed?" first). */
    public function unsend(Request $request, string $patientUid, string $messageId): RedirectResponse
    {
        [$thread] = $this->authorizeThread($request, $patientUid);

        return $this->runAction($patientUid, 'Message not unsent.', fn () => $this->actions->unsend($request->user(), $patientUid, $thread, $messageId));
    }

    /** Pin any message of this conversation for both sides. */
    public function pin(Request $request, string $patientUid, string $messageId): RedirectResponse
    {
        [$thread] = $this->authorizeThread($request, $patientUid);

        return $this->runAction($patientUid, 'Message not pinned.', fn () => $this->actions->pin($request->user(), $patientUid, $thread, $messageId));
    }

    /** Remove this conversation's pin. */
    public function unpin(Request $request, string $patientUid): RedirectResponse
    {
        [$thread] = $this->authorizeThread($request, $patientUid);

        return $this->runAction($patientUid, 'Message not unpinned.', fn () => $this->actions->unpin($request->user(), $patientUid, $thread));
    }

    /**
     * Run a chat action and go back to the conversation. Like sending, success
     * shows no banner: the changed bubble or banner is the confirmation.
     * Someone else's message is a 403, a message that isn't in this thread a
     * 404; a rule (edit window, already unsent) or a Firebase failure comes
     * back as an error banner.
     */
    private function runAction(string $patientUid, string $failed, \Closure $action): RedirectResponse
    {
        try {
            $action();
        } catch (ChatActionException $e) {
            abort_if($e->getCode() === ChatActionException::NOT_FOUND, 404);
            abort_if($e->getCode() === ChatActionException::FORBIDDEN, 403, $e->getMessage());
            Log::info('messages.action_rejected', ['uid' => auth()->id(), 'patient' => $patientUid, 'reason' => $e->getMessage()]);

            return redirect()->route('messages.show', $patientUid)->with('error', "{$failed} {$e->getMessage()}");
        } catch (FirebaseException $e) {
            report($e);

            return redirect()->route('messages.show', $patientUid)->with('error', "{$failed} {$e->getMessage()}");
        }

        return redirect()->route('messages.show', $patientUid);
    }

    /**
     * Load the messages and clear the unread badge, in parallel, then add
     * read receipts and the pinned banner from the thread summary that
     * markRead() read, and each bubble's menu for this staff member.
     *
     * @return array{0: array, 1: string, 2: ?array} messages, the thread version and the pin
     */
    private function loadAndMarkRead(Request $request, string $patientUid, string $thread, array $patient): array
    {
        try {
            [$messages, $summary] = $this->firebase->concurrently([
                fn () => $this->messaging->messages($patientUid, $thread, $patient),
                function () use ($patientUid, $thread) {
                    try {
                        return $this->messaging->markRead($patientUid, $thread);
                    } catch (FirebaseException $e) {
                        report($e); // the badge stays and ticks show as 'sent'; not worth failing the page over

                        return null;
                    }
                },
            ]);
        } catch (FirebaseException $e) {
            report($e);
            abort(503, 'Could not reach Firebase. Try again in a moment.');
        }

        // The Messages tab badge is cached for 30 seconds; drop it so the opened chat is no longer counted.
        Cache::forget('messages-unread:'.auth()->id());

        $pinned = MessagePresenter::pinned($summary, $messages);
        $messages = MessagePresenter::withActions(
            MessagingService::withReadReceipts($messages, $summary),
            $request->user(),
            canReply: empty($patient['archived']), // archived patients have no composer
            pinnedId: $pinned['id'] ?? null,
        );

        return [$messages, MessagingService::version($summary), $pinned];
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
