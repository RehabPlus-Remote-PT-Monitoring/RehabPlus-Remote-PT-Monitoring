<?php

namespace Tests\Feature;

use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** Messages between administrators and physical therapists (staffChats in Firestore). */
class StaffChatTest extends TestCase
{
    use FakeFirebase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->staff('admin', 'adm1', 'Front Desk');
        $this->staff('therapist', 'thA', 'Dr. Lee');
        $this->staff('therapist', 'thB', 'Dr. Ben');
    }

    /** Messages in the conversation between two people, in any order. */
    private function messagesBetween(string $a, string $b): array
    {
        $pair = [$a, $b];
        sort($pair);

        return array_values(array_filter(
            $this->docsLike("staffChats/{$pair[0]}__{$pair[1]}/messages/*"),
        ));
    }

    public function test_an_administrator_and_a_therapist_can_message_each_other(): void
    {
        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'))
            ->post('/messages/staff/thA', ['text' => 'Can you move Kesh to 2 PM?'])
            ->assertRedirect('/messages/staff/thA');

        $messages = $this->messagesBetween('adm1', 'thA');
        $this->assertCount(1, $messages);
        $message = array_values($messages)[0];
        $this->assertSame('Can you move Kesh to 2 PM?', $message['text']);
        $this->assertSame('adm1', $message['senderId']);
        $this->assertSame('Front Desk', $message['senderName']);

        // The reply goes the other way, into the same conversation.
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Lee'))
            ->post('/messages/staff/adm1', ['text' => 'Yes, that works.'])
            ->assertRedirect('/messages/staff/adm1');

        $this->assertCount(2, $this->messagesBetween('adm1', 'thA'));
    }

    public function test_the_receiver_gets_an_unread_count_until_they_open_the_chat(): void
    {
        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'))
            ->post('/messages/staff/thA', ['text' => 'First'])->assertRedirect();
        $this->post('/messages/staff/thA', ['text' => 'Second'])->assertRedirect();

        $this->assertSame(2, $this->docs['staffChats/adm1__thA']['unread_thA']);

        $therapist = $this->staff('therapist', 'thA', 'Dr. Lee');
        $this->actingAs($therapist)->get('/messages')->assertOk()
            ->assertSee('aria-label="2 unread"', false);

        $this->get('/messages/staff/adm1')->assertOk()->assertSee('First')->assertSee('Second');
        $this->assertSame(0, $this->docs['staffChats/adm1__thA']['unread_thA']);

        $this->get('/messages')->assertOk()->assertDontSee('aria-label="2 unread"', false);
    }

    public function test_the_directory_lists_other_active_staff_only(): void
    {
        $this->staff('therapist', 'thOff', 'Dr. Off');
        $this->docs['users/thOff']['active'] = false;
        $this->staff('therapist', 'thGone', 'Dr. Gone');
        $this->docs['users/thGone']['archived'] = true;
        $this->patientDoc('pOne', ['name' => 'Maria Patient']);

        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Lee'))->get('/messages')->assertOk()
            ->assertSee('Front Desk')
            ->assertSee('Dr. Ben')
            ->assertDontSee('href="'.url('/messages/staff/thA').'"', false) // yourself
            ->assertDontSee('Dr. Off')
            ->assertDontSee('Dr. Gone')
            ->assertDontSee('Maria Patient');
    }

    public function test_people_who_cannot_be_messaged_are_not_found(): void
    {
        $this->staff('therapist', 'thOff', 'Dr. Off');
        $this->docs['users/thOff']['active'] = false;
        $this->staff('therapist', 'thGone', 'Dr. Gone');
        $this->docs['users/thGone']['archived'] = true;
        $this->patientDoc('pOne');

        $me = $this->actingAs($this->staff('therapist', 'thA', 'Dr. Lee'));

        $me->get('/messages/staff/thA')->assertNotFound();      // yourself
        $me->get('/messages/staff/thOff')->assertNotFound();    // disabled
        $me->get('/messages/staff/thGone')->assertNotFound();   // archived
        $me->get('/messages/staff/pOne')->assertNotFound();     // a patient, not staff
        $me->get('/messages/staff/nope')->assertNotFound();     // no such account
        $me->post('/messages/staff/pOne', ['text' => 'Hello'])->assertNotFound();

        $this->assertSame([], $this->docsLike('staffChats/*/messages/*'));
    }

    public function test_an_empty_message_is_not_saved(): void
    {
        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'))
            ->post('/messages/staff/thA', ['text' => '   '])
            ->assertSessionHasErrors('text');

        $this->assertSame([], $this->docsLike('staffChats/*/messages/*'));
    }

    public function test_the_staff_accounts_page_has_a_message_button_for_other_active_staff(): void
    {
        $this->staff('therapist', 'thOff', 'Dr. Off');
        $this->docs['users/thOff']['active'] = false;

        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'))->get('/users')->assertOk()
            ->assertSee('href="'.url('/messages/staff/thA').'"', false)
            ->assertSee('href="'.url('/messages/staff/thB').'"', false)
            ->assertDontSee('href="'.url('/messages/staff/thOff').'"', false)
            ->assertDontSee('href="'.url('/messages/staff/adm1').'"', false);
    }

    public function test_the_messages_tab_lists_patients_and_staff_together_with_their_role(): void
    {
        $this->patientDoc('pAnna', ['name' => 'Anna Cruz', 'therapistId' => 'thA']);
        $this->docs['patients/pAnna/threads/therapist'] = ['lastMessage' => 'My knee hurts', 'lastMessageAt' => \Carbon\CarbonImmutable::now(), 'lastSenderRole' => 'patient', 'unreadForStaff' => 0];
        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'))->get('/messages')->assertOk()
            ->assertSee('Anna Cruz')
            ->assertSee('>Patient</span>', false)
            ->assertSee('Dr. Lee')
            ->assertSee('Dr. Ben')
            ->assertSee('>Physical Therapist</span>', false)
            ->assertSee('id="conversation-search"', false)
            ->assertSee('data-conversation-row', false);
    }

    public function test_the_staff_conversation_shows_the_role_and_a_way_back_to_messages(): void
    {
        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'))->get('/messages/staff/thA')->assertOk()
            ->assertSee('Dr. Lee')
            ->assertSee('>Physical Therapist</span>', false)
            ->assertSee('href="'.route('messages.index').'"', false);
    }

    public function test_staff_conversations_are_not_in_the_archive(): void
    {
        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'))->get('/messages?archived=1')->assertOk()
            ->assertDontSee('Dr. Lee')
            ->assertDontSee('Dr. Ben');
    }

    public function test_the_old_staff_messages_page_is_gone(): void
    {
        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'))->get('/staff-chat')->assertNotFound();
    }

    public function test_every_staff_member_sees_the_messages_link(): void
    {
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Lee'))->get('/dashboard')->assertOk()
            ->assertSee('href="'.url('/messages').'"', false);
    }
}
