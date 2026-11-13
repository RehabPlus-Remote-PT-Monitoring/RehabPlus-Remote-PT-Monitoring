<?php

namespace Tests\Feature;

use Carbon\CarbonImmutable;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/**
 * The "⋮" menu on chat bubbles: reply quotes, edit, unsend, pin / unpin, and
 * how the new optional message fields render (docs/superpowers/specs/
 * 2026-11-13-chat-actions-design.md). Runs against the fake Firestore, so
 * write payloads are asserted exactly and nothing reaches Firebase.
 */
class ChatActionsTest extends TestCase
{
    use FakeFirebase;

    private const THREAD = 'patients/pAnna/threads/therapist';

    private CarbonImmutable $now;

    protected function setUp(): void
    {
        parent::setUp();

        $this->now = CarbonImmutable::parse('2026-11-13 10:00:00');
        CarbonImmutable::setTestNow($this->now);
        $now = $this->now;

        $this->docs += [
            'patients/pAnna' => ['name' => 'Anna Cruz', 'therapistId' => 'therapistUid1', 'therapistName' => 'Dr. Reyes'],
            'patients/pBen' => ['name' => 'Ben Lim', 'therapistId' => 'otherTherapist'],
            'patients/pOld' => ['name' => 'Olga Archived', 'therapistId' => 'therapistUid1', 'archived' => true],
            self::THREAD => [
                'lastMessage' => 'And rest after.', 'lastMessageAt' => $now->subMinute(), 'lastSenderRole' => 'staff',
                'unreadForPatient' => 1, 'unreadForStaff' => 0,
            ],
            self::THREAD.'/messages/p1' => ['text' => 'My knee hurts after squats', 'senderId' => 'pAnna', 'senderRole' => 'patient', 'sentAt' => $now->subMinutes(30), 'createdAt' => $now->subMinutes(30)],
            self::THREAD.'/messages/old1' => ['text' => 'Sent an hour ago', 'senderId' => 'therapistUid1', 'senderRole' => 'staff', 'senderName' => 'Dr. Reyes', 'sentAt' => $now->subMinutes(20), 'createdAt' => $now->subMinutes(20)],
            self::THREAD.'/messages/prev1' => ['text' => 'From the previous therapist', 'senderId' => 'formerTherapist', 'senderRole' => 'staff', 'senderName' => 'Dr. Former', 'sentAt' => $now->subMinutes(10), 'createdAt' => $now->subMinutes(10)],
            self::THREAD.'/messages/s1' => ['text' => 'Do 10 squats.', 'senderId' => 'therapistUid1', 'senderRole' => 'staff', 'senderName' => 'Dr. Reyes', 'sentAt' => $now->subMinutes(2), 'createdAt' => $now->subMinutes(2)],
            self::THREAD.'/messages/s2' => [
                'text' => 'And rest after.', 'senderId' => 'therapistUid1', 'senderRole' => 'staff', 'senderName' => 'Dr. Reyes',
                'sentAt' => $now->subMinute(), 'createdAt' => $now->subMinute(),
                'replyTo' => ['id' => 'p1', 'text' => 'My knee hurts after squats', 'senderRole' => 'patient'],
            ],
            'patients/pBen/threads/therapist/messages/b1' => ['text' => 'Ben here', 'senderRole' => 'patient', 'sentAt' => $now->subMinutes(5)],
            'patients/pBen/threads/clinic/messages/bc1' => ['text' => 'Clinic question', 'senderRole' => 'patient', 'sentAt' => $now->subMinutes(5)],
            'patients/pAnna/devices/goodToken' => ['token' => 'goodToken'],
        ];
    }

    protected function tearDown(): void
    {
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    private function therapist()
    {
        return $this->staff('therapist', 'therapistUid1', 'Dr. Reyes');
    }

    /** The feed's HTML split into one chunk per message row, found by its text. */
    private function row(string $html, string $text): string
    {
        $rows = preg_split('/(?=<div class="d-flex flex-column)/', $html);

        return (string) collect($rows)->first(fn ($r) => str_contains($r, $text));
    }

    // ---- edit -----------------------------------------------------------

    public function test_editing_the_newest_own_message_updates_it_and_the_preview_only(): void
    {
        $this->actingAs($this->therapist())
            ->post('/messages/pAnna/s2/edit', ['text' => '  And rest for a day.  '])
            ->assertRedirect('/messages/pAnna')
            ->assertSessionMissing('success')
            ->assertSessionMissing('error');

        $this->assertCount(1, $this->commits, 'one atomic commit');
        [$message, $thread] = $this->commits[0];

        $this->assertSame(self::ROOT.'/'.self::THREAD.'/messages/s2', $message['update']['name']);
        $this->assertSame(['text' => ['stringValue' => 'And rest for a day.']], $message['update']['fields']);
        $this->assertSame(['text'], $message['updateMask']['fieldPaths']);
        $this->assertSame([['fieldPath' => 'editedAt', 'setToServerValue' => 'REQUEST_TIME']], $message['updateTransforms']);
        $this->assertArrayHasKey('updateTime', $message['currentDocument'], 'guarded against a parallel change');

        $this->assertSame(self::ROOT.'/'.self::THREAD, $thread['update']['name']);
        $this->assertSame(['lastMessage' => ['stringValue' => 'And rest for a day.']], $thread['update']['fields']);
        $this->assertSame(['lastMessage'], $thread['updateMask']['fieldPaths'], 'lastMessageAt and unread counters untouched');
        $this->assertSame([['fieldPath' => 'lastActionAt', 'setToServerValue' => 'REQUEST_TIME']], $thread['updateTransforms'], 'no unread bump');
        $this->assertArrayHasKey('updateTime', $thread['currentDocument']);

        $this->assertSame(1, $this->docs[self::THREAD]['unreadForPatient']);
        $this->assertInstanceOf(CarbonImmutable::class, $this->docs[self::THREAD.'/messages/s2']['editedAt']);
        $this->assertSame([], $this->pushes, 'no push for an edit');
    }

    public function test_editing_an_older_own_message_keeps_the_preview_but_marks_the_thread(): void
    {
        $this->actingAs($this->therapist())->post('/messages/pAnna/s1/edit', ['text' => 'Do 12 squats.'])
            ->assertRedirect('/messages/pAnna')->assertSessionMissing('error');

        [$message, $thread] = $this->commits[0];
        $this->assertSame(self::ROOT.'/'.self::THREAD.'/messages/s1', $message['update']['name']);
        // Only lastActionAt, so open pages reload; preview and counters untouched.
        $this->assertSame([], $thread['updateMask']['fieldPaths']);
        $this->assertSame([['fieldPath' => 'lastActionAt', 'setToServerValue' => 'REQUEST_TIME']], $thread['updateTransforms']);
        $this->assertSame('And rest after.', $this->docs[self::THREAD]['lastMessage']);
    }

    public function test_editing_the_pinned_message_refreshes_the_banner_text(): void
    {
        $this->docs[self::THREAD] += ['pinnedMessageId' => 's1', 'pinnedText' => 'Do 10 squats.', 'pinnedSenderRole' => 'staff', 'pinnedAt' => $this->now];

        $this->actingAs($this->therapist())->post('/messages/pAnna/s1/edit', ['text' => 'Do 12 squats.'])
            ->assertSessionMissing('error');

        $this->assertSame('Do 12 squats.', $this->docs[self::THREAD]['pinnedText']);
        $this->assertSame('s1', $this->docs[self::THREAD]['pinnedMessageId']);
    }

    public function test_unchanged_text_writes_nothing(): void
    {
        $this->actingAs($this->therapist())->post('/messages/pAnna/s1/edit', ['text' => 'Do 10 squats.'])
            ->assertRedirect('/messages/pAnna')->assertSessionMissing('error');

        $this->assertSame([], $this->commits);
    }

    public function test_edit_window_closes_after_fifteen_minutes(): void
    {
        // s2 was saved a minute before $this->now.
        CarbonImmutable::setTestNow($this->now->addMinutes(13)->addSeconds(59));
        $this->actingAs($this->therapist())->post('/messages/pAnna/s2/edit', ['text' => 'Still in time'])
            ->assertSessionMissing('error');

        CarbonImmutable::setTestNow($this->now->addMinutes(14));
        $this->actingAs($this->therapist())->post('/messages/pAnna/s2/edit', ['text' => 'Too late'])
            ->assertRedirect('/messages/pAnna')
            ->assertSessionHas('error', fn ($m) => str_contains($m, 'within 15 minutes'));

        $this->assertCount(1, $this->commits);
    }

    public function test_cannot_edit_someone_elses_or_a_patients_message(): void
    {
        $user = $this->therapist();
        $this->actingAs($user)->post('/messages/pAnna/prev1/edit', ['text' => 'x'])->assertForbidden();
        $this->actingAs($user)->post('/messages/pAnna/p1/edit', ['text' => 'x'])->assertForbidden();

        $this->assertSame([], $this->commits);
    }

    public function test_cannot_edit_an_unsent_message_or_a_session_card(): void
    {
        $this->docs[self::THREAD.'/messages/s1'] = ['text' => '', 'unsent' => true] + $this->docs[self::THREAD.'/messages/s1'];
        $this->docs[self::THREAD.'/messages/card'] = [
            'text' => 'Squats summary', 'senderId' => 'therapistUid1', 'senderRole' => 'staff',
            'sentAt' => $this->now->subMinutes(3), 'createdAt' => $this->now->subMinutes(3),
            'session' => ['exerciseName' => 'Squats'],
        ];
        $user = $this->therapist();

        $this->actingAs($user)->post('/messages/pAnna/s1/edit', ['text' => 'x'])
            ->assertSessionHas('error', fn ($m) => str_contains($m, 'unsent'));
        $this->actingAs($user)->post('/messages/pAnna/card/edit', ['text' => 'x'])
            ->assertSessionHas('error', fn ($m) => str_contains($m, 'session card'));

        $this->assertSame([], $this->commits);
    }

    public function test_edit_text_is_validated(): void
    {
        $user = $this->therapist();
        $this->actingAs($user)->post('/messages/pAnna/s2/edit', ['text' => ''])->assertSessionHasErrors('text');
        $this->actingAs($user)->post('/messages/pAnna/s2/edit', ['text' => str_repeat('a', 1001)])->assertSessionHasErrors('text');
        $this->actingAs($user)->post('/messages/pAnna/s2/edit', ['text' => '   '])->assertSessionHasErrors('text');

        $this->assertSame([], $this->commits);
    }

    public function test_actions_are_scoped_like_the_conversation(): void
    {
        $this->post('/messages/pAnna/s1/pin')->assertRedirect('/login');

        $user = $this->therapist();

        // Another therapist's patient: 404 for every action, before any message is read.
        $this->actingAs($user)->post('/messages/pBen/b1/edit', ['text' => 'x'])->assertNotFound();
        $this->actingAs($user)->post('/messages/pBen/b1/unsend')->assertNotFound();
        $this->actingAs($user)->post('/messages/pBen/b1/pin')->assertNotFound();
        $this->actingAs($user)->post('/messages/pBen/unpin')->assertNotFound();

        // A message id from another thread, a missing one, and a malformed one.
        $this->actingAs($user)->post('/messages/pAnna/bc1/pin')->assertNotFound();
        $this->actingAs($user)->post('/messages/pAnna/nope/unsend')->assertNotFound();
        $this->actingAs($user)->post('/messages/pAnna/'.urlencode('s1.x').'/pin')->assertNotFound();

        $this->assertSame([], $this->commits);
    }

    public function test_edit_loses_a_race_with_a_parallel_change(): void
    {
        // The patient's app (or another tab) changes the message between read and write.
        $this->beforeNextCommit = function () {
            $this->docs[self::THREAD.'/messages/s1']['text'] = 'Changed elsewhere';
        };

        $this->actingAs($this->therapist())->post('/messages/pAnna/s1/edit', ['text' => 'Mine'])
            ->assertRedirect('/messages/pAnna')
            ->assertSessionHas('error', fn ($m) => str_contains($m, 'Someone else changed'));

        $this->assertSame([], $this->commits);
        $this->assertSame('Changed elsewhere', $this->docs[self::THREAD.'/messages/s1']['text']);
    }

    // ---- clinic thread: senderId is "clinic", so the staff uid decides ----

    public function test_clinic_staff_can_edit_only_their_own_clinic_messages(): void
    {
        $now = $this->now;
        $this->docs += [
            'patients/pBen/threads/clinic' => ['lastMessage' => 'Tuesday works.', 'lastMessageAt' => $now],
            'patients/pBen/threads/clinic/messages/mine' => ['text' => 'Tuesday works.', 'senderId' => 'clinic', 'senderRole' => 'staff', 'senderStaffUid' => 'adminUid', 'sentAt' => $now, 'createdAt' => $now],
            'patients/pBen/threads/clinic/messages/colleague' => ['text' => 'Hi Ben', 'senderId' => 'clinic', 'senderRole' => 'staff', 'senderStaffUid' => 'admin2', 'sentAt' => $now->subMinute(), 'createdAt' => $now->subMinute()],
            'patients/pBen/threads/clinic/messages/legacy' => ['text' => 'Before the uid was stored', 'senderId' => 'clinic', 'senderRole' => 'staff', 'sentAt' => $now->subMinutes(2), 'createdAt' => $now->subMinutes(2)],
        ];
        $admin = $this->staff('admin');

        $this->actingAs($admin)->post('/messages/pBen/colleague/edit', ['text' => 'x'])->assertForbidden();
        $this->actingAs($admin)->post('/messages/pBen/legacy/unsend')->assertForbidden();
        $this->actingAs($admin)->post('/messages/pBen/mine/edit', ['text' => 'Tuesday 10am works.'])
            ->assertRedirect('/messages/pBen')->assertSessionMissing('error');

        $this->assertCount(1, $this->commits);
        $this->assertSame('Tuesday 10am works.', $this->docs['patients/pBen/threads/clinic']['lastMessage']);
    }

    // ---- unsend ---------------------------------------------------------

    public function test_unsending_the_newest_pinned_message_clears_it_the_pin_and_the_preview(): void
    {
        $this->docs[self::THREAD] += ['pinnedMessageId' => 's2', 'pinnedText' => 'And rest after.', 'pinnedSenderRole' => 'staff', 'pinnedAt' => $this->now];
        $this->docs[self::THREAD.'/messages/s2']['session'] = ['exerciseName' => 'stray']; // removed too

        $this->actingAs($this->therapist())->post('/messages/pAnna/s2/unsend')
            ->assertRedirect('/messages/pAnna')
            ->assertSessionMissing('success')
            ->assertSessionMissing('error');

        $this->assertCount(1, $this->commits);
        [$message, $thread] = $this->commits[0];

        $this->assertSame(['text' => ['stringValue' => ''], 'unsent' => ['booleanValue' => true]], $message['update']['fields']);
        $this->assertSame(['text', 'unsent', 'replyTo', 'session'], $message['updateMask']['fieldPaths'], 'replyTo/session deleted via the mask');
        $this->assertSame([['fieldPath' => 'unsentAt', 'setToServerValue' => 'REQUEST_TIME']], $message['updateTransforms']);
        $this->assertArrayHasKey('updateTime', $message['currentDocument']);

        $this->assertSame(['lastMessage' => ['stringValue' => 'Message deleted']], $thread['update']['fields']);
        $this->assertSame(['lastMessage', 'pinnedMessageId', 'pinnedText', 'pinnedSenderRole', 'pinnedAt'], $thread['updateMask']['fieldPaths']);
        $this->assertSame([['fieldPath' => 'lastActionAt', 'setToServerValue' => 'REQUEST_TIME']], $thread['updateTransforms'], 'no unread bump');
        $this->assertArrayHasKey('updateTime', $thread['currentDocument']);

        $doc = $this->docs[self::THREAD.'/messages/s2'];
        $this->assertTrue($doc['unsent']);
        $this->assertSame('', $doc['text']);
        $this->assertArrayNotHasKey('replyTo', $doc);
        $this->assertArrayNotHasKey('session', $doc);
        $this->assertArrayNotHasKey('pinnedMessageId', $this->docs[self::THREAD]);
        $this->assertSame(1, $this->docs[self::THREAD]['unreadForPatient']);
        $this->assertSame([], $this->pushes);
    }

    public function test_unsending_an_older_unpinned_message_keeps_the_preview_but_marks_the_thread(): void
    {
        // Allowed any time, unlike edit.
        $this->actingAs($this->therapist())->post('/messages/pAnna/old1/unsend')->assertSessionMissing('error');

        [, $thread] = $this->commits[0];
        $this->assertSame([], $thread['updateMask']['fieldPaths']);
        $this->assertSame([['fieldPath' => 'lastActionAt', 'setToServerValue' => 'REQUEST_TIME']], $thread['updateTransforms']);
        $this->assertSame('And rest after.', $this->docs[self::THREAD]['lastMessage']);
    }

    public function test_status_version_changes_when_an_older_message_is_edited_or_unsent(): void
    {
        $user = $this->therapist();
        $version = fn () => $this->actingAs($user)->getJson('/messages/pAnna/status')->assertOk()->json('version');

        $before = $version();
        // E.g. the patient unsent an older message from the app.
        $this->docs[self::THREAD]['lastActionAt'] = $this->now->addSecond();
        $this->assertNotSame($before, $version());
    }

    public function test_cannot_unsend_others_messages_or_twice(): void
    {
        $user = $this->therapist();
        $this->actingAs($user)->post('/messages/pAnna/p1/unsend')->assertForbidden();
        $this->actingAs($user)->post('/messages/pAnna/prev1/unsend')->assertForbidden();

        $this->actingAs($user)->post('/messages/pAnna/s1/unsend')->assertSessionMissing('error');
        $this->actingAs($user)->post('/messages/pAnna/s1/unsend')
            ->assertSessionHas('error', fn ($m) => str_contains($m, 'already unsent'));

        $this->assertCount(1, $this->commits);
    }

    // ---- pin / unpin ----------------------------------------------------

    public function test_pin_stores_a_snippet_on_the_thread(): void
    {
        $this->docs[self::THREAD.'/messages/p1']['text'] = str_repeat('Long text ', 40);

        $this->actingAs($this->therapist())->post('/messages/pAnna/p1/pin')
            ->assertRedirect('/messages/pAnna')->assertSessionMissing('error');

        $this->assertCount(1, $this->commits[0]);
        $write = $this->commits[0][0];
        $this->assertSame(self::ROOT.'/'.self::THREAD, $write['update']['name']);
        $this->assertSame(['pinnedMessageId', 'pinnedText', 'pinnedSenderRole'], $write['updateMask']['fieldPaths']);
        $this->assertSame([['fieldPath' => 'pinnedAt', 'setToServerValue' => 'REQUEST_TIME']], $write['updateTransforms']);
        $this->assertSame('p1', $write['update']['fields']['pinnedMessageId']['stringValue']);
        $this->assertSame('patient', $write['update']['fields']['pinnedSenderRole']['stringValue']);
        $this->assertLessThanOrEqual(200, mb_strlen($write['update']['fields']['pinnedText']['stringValue']));
        $this->assertSame(1, $this->docs[self::THREAD]['unreadForPatient']);
        $this->assertSame([], $this->pushes);
    }

    public function test_cannot_pin_an_unsent_message(): void
    {
        $this->docs[self::THREAD.'/messages/s1'] = ['text' => '', 'unsent' => true] + $this->docs[self::THREAD.'/messages/s1'];

        $this->actingAs($this->therapist())->post('/messages/pAnna/s1/pin')
            ->assertSessionHas('error', fn ($m) => str_contains($m, 'unsent'));
        $this->assertSame([], $this->commits);
    }

    public function test_unpin_deletes_the_four_pin_fields(): void
    {
        $this->docs[self::THREAD] += ['pinnedMessageId' => 'p1', 'pinnedText' => 'My knee', 'pinnedSenderRole' => 'patient', 'pinnedAt' => $this->now];

        $this->actingAs($this->therapist())->post('/messages/pAnna/unpin')
            ->assertRedirect('/messages/pAnna')->assertSessionMissing('error');

        $write = $this->commits[0][0];
        $this->assertSame(['name' => self::ROOT.'/'.self::THREAD], $write['update'], 'no values: the mask deletes them');
        $this->assertSame(['pinnedMessageId', 'pinnedText', 'pinnedSenderRole', 'pinnedAt'], $write['updateMask']['fieldPaths']);
        $this->assertArrayHasKey('updateTime', $write['currentDocument']);
        $this->assertArrayNotHasKey('pinnedAt', $this->docs[self::THREAD]);
        $this->assertSame('And rest after.', $this->docs[self::THREAD]['lastMessage']);

        // Nothing pinned any more: no write at all.
        $this->actingAs($this->therapist())->post('/messages/pAnna/unpin')->assertSessionMissing('error');
        $this->assertCount(1, $this->commits);
    }

    // ---- reply quotes -----------------------------------------------------

    public function test_reply_to_a_message_stores_a_quote(): void
    {
        $this->docs[self::THREAD.'/messages/p1']['text'] = str_repeat('ouch ', 100);

        $this->actingAs($this->therapist())
            ->post('/messages/pAnna', ['text' => 'Ice it.', 'reply_to_id' => 'p1'])
            ->assertRedirect('/messages/pAnna')
            ->assertSessionMissing('success')
            ->assertSessionMissing('error');

        $fields = $this->commits[0][0]['update']['fields'];
        $quote = $fields['replyTo']['mapValue']['fields'];
        $this->assertSame('p1', $quote['id']['stringValue']);
        $this->assertSame('patient', $quote['senderRole']['stringValue']);
        $this->assertLessThanOrEqual(200, mb_strlen($quote['text']['stringValue']));
        $this->assertStringStartsWith('ouch ouch', $quote['text']['stringValue']);
        $this->assertSame('therapistUid1', $fields['senderStaffUid']['stringValue']);
        $this->assertCount(3, $this->commits[0], 'message, thread and notification as before');
    }

    public function test_reply_without_a_quote_has_no_reply_to_field(): void
    {
        $this->actingAs($this->therapist())->post('/messages/pAnna', ['text' => 'Hello', 'reply_to_id' => ''])
            ->assertSessionMissing('error');

        $this->assertArrayNotHasKey('replyTo', $this->commits[0][0]['update']['fields']);
    }

    public function test_reply_to_a_message_from_another_thread_is_rejected(): void
    {
        $user = $this->therapist();
        foreach (['bc1', 'b1', 'nope', 'bad/id'] as $id) {
            $this->actingAs($user)->post('/messages/pAnna', ['text' => 'Hi', 'reply_to_id' => $id])
                ->assertSessionHas('error', fn ($m) => str_contains($m, 'Message not sent'));
        }

        $this->docs[self::THREAD.'/messages/s1']['unsent'] = true;
        $this->actingAs($user)->post('/messages/pAnna', ['text' => 'Hi', 'reply_to_id' => 's1'])
            ->assertSessionHas('error', fn ($m) => str_contains($m, 'unsent'));

        $this->assertSame([], $this->commits);
        $this->assertSame([], $this->pushes);
    }

    // ---- rendering ----------------------------------------------------------

    public function test_feed_renders_quotes_edited_unsent_and_the_pinned_banner(): void
    {
        $now = $this->now;
        $this->docs[self::THREAD] += ['pinnedMessageId' => 'p1', 'pinnedText' => 'My knee hurts after squats', 'pinnedSenderRole' => 'patient', 'pinnedAt' => $now];
        $this->docs[self::THREAD.'/messages/s1']['editedAt'] = $now;
        $this->docs[self::THREAD.'/messages/u1'] = ['text' => '', 'unsent' => true, 'senderId' => 'therapistUid1', 'senderRole' => 'staff', 'sentAt' => $now->subMinutes(4), 'createdAt' => $now->subMinutes(4)];
        $this->docs[self::THREAD.'/messages/u2'] = ['text' => '', 'unsent' => true, 'senderId' => 'pAnna', 'senderRole' => 'patient', 'sentAt' => $now->subMinutes(3), 'createdAt' => $now->subMinutes(3)];

        $html = $this->actingAs($this->therapist())->get('/messages/pAnna/feed')->assertOk()->getContent();

        // Reply quote with the quoted sender's name, inside the reply's bubble.
        $reply = $this->row($html, 'And rest after.');
        $this->assertStringContainsString('class="chat-quote"', $reply);
        $this->assertStringContainsString('data-chat-scroll-to="p1"', $reply);
        $this->assertStringContainsString('Anna Cruz', $reply);

        $this->assertStringContainsString('Edited', $this->row($html, 'Do 10 squats.'));
        $this->assertStringNotContainsString('Edited', $reply);

        // Own unsent vs the patient's unsent; no ticks or menu on either.
        $mine = $this->row($html, 'id="msg-u1"');
        $this->assertStringContainsString('You deleted a message', $mine);
        $this->assertStringNotContainsString('chat-tick', $mine);
        $this->assertStringNotContainsString('data-chat-menu-toggle', $mine);
        $this->assertStringContainsString('Message deleted', $this->row($html, 'id="msg-u2"'));

        // Pinned banner first, pointing at the message on the page.
        $this->assertStringContainsString('data-chat-pinned', $html);
        $this->assertLessThan(strpos($html, 'id="msg-p1"'), strpos($html, 'data-chat-pinned'));
        $this->assertStringContainsString('Pinned · Anna Cruz', $html);
        $this->assertStringContainsString('action="http://localhost/messages/pAnna/unpin"', $html);
    }

    public function test_menu_offers_only_the_allowed_actions(): void
    {
        $html = $this->actingAs($this->therapist())->get('/messages/pAnna')->assertOk()->getContent();

        $own = $this->row($html, 'Do 10 squats.');
        foreach (['data-chat-reply', 'data-chat-edit', 'data-chat-copy', 'data-chat-pin', 'data-chat-unsend', 'data-edit-until='] as $item) {
            $this->assertStringContainsString($item, $own, $item);
        }
        $this->assertStringContainsString('data-confirm="Unsend this message?', $own);
        $this->assertStringContainsString('data-confirm-danger', $own);
        // Reply is its own button next to the bubble, before (outside) the "⋯" menu.
        $this->assertLessThan(strpos($own, 'data-chat-menu-toggle'), strpos($own, 'data-chat-reply'));
        $this->assertStringContainsString('bi-three-dots"', $own);

        $patient = $this->row($html, 'My knee hurts after squats');
        $this->assertStringContainsString('data-chat-reply', $patient);
        $this->assertStringContainsString('data-chat-pin', $patient);
        $this->assertStringNotContainsString('data-chat-edit', $patient);
        $this->assertStringNotContainsString('data-chat-unsend', $patient);

        // Own but older than 15 minutes: unsend yes, edit no.
        $old = $this->row($html, 'Sent an hour ago');
        $this->assertStringNotContainsString('data-chat-edit', $old);
        $this->assertStringContainsString('data-chat-unsend', $old);

        // A colleague's message: not own.
        $colleague = $this->row($html, 'From the previous therapist');
        $this->assertStringNotContainsString('data-chat-edit', $colleague);
        $this->assertStringNotContainsString('data-chat-unsend', $colleague);

        // Composer carries the reply id and its preview.
        $this->assertStringContainsString('name="reply_to_id"', $html);
        $this->assertStringContainsString('data-reply-preview', $html);
    }

    public function test_pinned_message_shows_unpin_in_its_menu(): void
    {
        $this->docs[self::THREAD] += ['pinnedMessageId' => 's1', 'pinnedText' => 'Do 10 squats.', 'pinnedSenderRole' => 'staff', 'pinnedAt' => $this->now];

        $html = $this->actingAs($this->therapist())->get('/messages/pAnna/feed')->getContent();

        $this->assertStringContainsString('data-chat-unpin', $this->row($html, 'id="msg-s1"'));
        $this->assertStringNotContainsString('data-chat-unpin', $this->row($html, 'id="msg-s2"'));
        $this->assertStringContainsString('data-chat-pin', $this->row($html, 'id="msg-s2"'));
    }

    public function test_archived_patients_get_no_reply_action(): void
    {
        $this->docs['patients/pOld/threads/therapist/messages/o1'] = ['text' => 'Old chat', 'senderRole' => 'patient', 'sentAt' => $this->now];

        $row = $this->row($this->actingAs($this->therapist())->get('/messages/pOld')->assertOk()->getContent(), 'Old chat');

        $this->assertStringNotContainsString('data-chat-reply', $row);
        $this->assertStringContainsString('data-chat-copy', $row);
    }

    public function test_session_card_shows_boxes_tones_and_note(): void
    {
        $this->docs[self::THREAD.'/messages/card'] = [
            'text' => 'Squats: 12/15 reps', 'senderId' => 'pAnna', 'senderRole' => 'patient', 'sentAt' => $this->now->subMinutes(3),
            'session' => [
                'exerciseName' => 'Wall squats', 'startTime' => CarbonImmutable::parse('2026-11-13 01:30:00'),
                'completedReps' => 12, 'targetReps' => 15, 'endedEarly' => false,
                'accuracy' => 86, 'painLevel' => 3, 'painNote' => 'A bit sore at the end',
            ],
        ];
        $this->docs[self::THREAD.'/messages/card2'] = [
            'text' => 'Lunges summary', 'senderId' => 'pAnna', 'senderRole' => 'patient', 'sentAt' => $this->now->subMinutes(3)->addSecond(),
            'session' => ['exerciseName' => 'Lunges', 'completedReps' => 5, 'targetReps' => 10, 'accuracy' => 42],
        ];

        $html = $this->actingAs($this->therapist())->get('/messages/pAnna/feed')->assertOk()->getContent();

        $card = $this->row($html, 'Wall squats');
        $this->assertStringContainsString('data-chat-session', $card);
        $this->assertStringContainsString('Shared session · ', $card);
        $this->assertStringContainsString('12/15', $card);
        $this->assertStringContainsString('chat-tone-good', $card);
        $this->assertStringContainsString('86%', $card);
        $this->assertStringContainsString('3/10', $card);
        $this->assertStringContainsString('A bit sore at the end', $card);
        $this->assertStringNotContainsString('chat-text', $card, 'the card replaces the plain-text summary');
        $this->assertStringNotContainsString('data-chat-edit', $card);

        $card2 = $this->row($html, 'Lunges');
        $this->assertStringContainsString('chat-tone-poor', $card2);
        $this->assertStringNotContainsString('data-stat="pain"', $card2, 'no pain box when painLevel is missing');
        $this->assertStringNotContainsString('chat-session-note', $card2);
    }

    public function test_malformed_new_fields_are_dropped_not_a_500(): void
    {
        $now = $this->now;
        $this->docs[self::THREAD] += ['pinnedMessageId' => ['not' => 'an id'], 'pinnedText' => ['x']];
        $this->docs[self::THREAD.'/messages/bad1'] = [
            'text' => 'Fallback text one', 'senderRole' => 'patient', 'sentAt' => $now->subMinutes(5),
            'session' => ['exerciseName' => ['nested' => 'map'], 'accuracy' => 'high'],
            'replyTo' => ['id' => ['x'], 'text' => 5],
            'editedAt' => 'yesterday',
        ];
        $this->docs[self::THREAD.'/messages/bad2'] = [
            'text' => 'Fallback text two', 'senderRole' => 'patient', 'sentAt' => $now->subMinutes(4),
            'session' => 'oops', 'replyTo' => 'oops', 'unsent' => 'yes',
        ];
        $this->docs[self::THREAD.'/messages/bad3'] = [
            'text' => ['not' => 'text'], 'senderRole' => 'patient', 'sentAt' => $now->subMinutes(4)->addSecond(),
            'session' => ['exerciseName' => 'Bridges', 'completedReps' => 5000, 'targetReps' => -1, 'accuracy' => 250, 'painLevel' => 11, 'painNote' => ['x'], 'startTime' => 'today'],
        ];

        $html = $this->actingAs($this->therapist())->get('/messages/pAnna/feed')->assertOk()->getContent();

        $one = $this->row($html, 'Fallback text one');
        $this->assertStringNotContainsString('data-chat-session', $one);
        $this->assertStringNotContainsString('chat-quote', $one);
        $this->assertStringNotContainsString('Edited', $one);
        $this->assertStringContainsString('Fallback text two', $html, "'yes' is not unsent");
        $this->assertStringNotContainsString('data-chat-pinned', $html);

        // Out-of-range values: the card stays, with only the exercise name.
        $three = $this->row($html, 'Bridges');
        $this->assertStringContainsString('data-chat-session', $three);
        $this->assertStringNotContainsString('chat-session-stats', $three);
        $this->assertStringNotContainsString('chat-session-note', $three);
        $this->assertStringContainsString('>Shared session</div>', $three);
    }

    public function test_status_version_changes_on_pin_and_on_editing_the_newest_message(): void
    {
        $user = $this->therapist();
        $version = fn () => $this->actingAs($user)->getJson('/messages/pAnna/status')->assertOk()->json('version');

        $before = $version();
        $this->actingAs($user)->post('/messages/pAnna/p1/pin');
        $pinned = $version();
        $this->assertNotSame($before, $pinned);

        $this->actingAs($user)->post('/messages/pAnna/s2/edit', ['text' => 'And rest a lot.']);
        $this->assertNotSame($pinned, $version());
    }
}
