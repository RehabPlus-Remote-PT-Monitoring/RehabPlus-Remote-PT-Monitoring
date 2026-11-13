<?php

namespace Tests\Feature;

use Carbon\CarbonImmutable;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/**
 * Notices between staff (the bell) and the physical therapist's view of their own
 * schedule: they can see it and ask for a change, but only admins edit it.
 */
class StaffNoticeTest extends TestCase
{
    use FakeFirebase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->staff('therapist', 'thA', 'Dr. Lee');
        $this->staff('therapist', 'thB', 'Dr. Ben');
        $this->staff('admin', 'adm1', 'Front Desk');
    }

    private function form(array $overrides = []): array
    {
        return $overrides + [
            'patient' => 'Emily Johnson',
            'therapist_id' => 'thA',
            'patient_condition' => 'Knee rehab',
            'contact_country' => 'PH',
            'contact' => '9175550101',
            'date' => '2026-10-20',
            'time' => '09:30',
            'session' => 'Mobility Session',
            'notes' => '',
            'status' => 'Upcoming',
        ];
    }

    /** Notices addressed to this uid, from the fake Firestore. */
    private function noticesFor(string $uid): array
    {
        return array_values(array_filter(
            $this->docsLike('staffNotices/*'),
            fn (array $doc) => ($doc['toId'] ?? null) === $uid,
        ));
    }

    private function appointment(string $id, string $therapistId, array $overrides = []): void
    {
        $this->docs["appointments/{$id}"] = $overrides + [
            'patient' => 'Kesh Mine', 'therapistId' => $therapistId, 'therapist' => 'Dr.',
            'patient_condition' => 'Knee rehab', 'contact' => '+639175550101',
            'date' => CarbonImmutable::now()->addDay()->toDateString(), 'time' => '9:30 AM',
            'session' => 'Mobility Session', 'notes' => null, 'status' => 'Upcoming', 'completed_at' => null,
        ];
    }

    public function test_scheduling_tells_the_therapist_with_the_full_details(): void
    {
        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'));

        $this->post('/appointments', $this->form())->assertRedirect('/appointments');

        $notices = $this->noticesFor('thA');
        $this->assertCount(1, $notices);
        $notice = array_values($notices)[0];
        $this->assertSame('appointment', $notice['type']);
        $this->assertSame('New appointment scheduled', $notice['title']);
        $this->assertFalse($notice['read']);
        $this->assertStringContainsString('Patient: Emily Johnson', $notice['body']);
        $this->assertStringContainsString('Mobility Session', $notice['body']);
        $this->assertSame('Front Desk', $notice['fromName']);
        $this->assertSame([], $this->noticesFor('thB'));
    }

    public function test_the_therapist_sees_the_notice_in_the_bell_and_can_open_it(): void
    {
        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'));
        $this->post('/appointments', $this->form())->assertRedirect('/appointments');

        $therapist = $this->staff('therapist', 'thA', 'Dr. Lee');
        $this->actingAs($therapist)->get('/dashboard')->assertOk()
            ->assertSee('data-notice-count="1"', false)
            ->assertSee('New appointment scheduled');

        $id = array_key_first(array_filter($this->docsLike('staffNotices/*'), fn ($doc) => $doc['toId'] === 'thA'));
        $id = explode('/', $id)[1];

        $this->get("/notices/{$id}")->assertRedirect();
        $this->assertTrue($this->docs["staffNotices/{$id}"]['read']);

        $this->actingAs($therapist)->get('/dashboard')->assertOk()
            ->assertSee('data-notice-count="0"', false);
    }

    public function test_an_update_or_status_change_notifies_the_therapist(): void
    {
        $this->appointment('ap1', 'thA');
        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'));

        $this->put('/appointments/ap1', $this->form(['time' => '10:00', 'status' => 'Upcoming']))->assertRedirect();
        $this->assertContains('Appointment updated', array_column($this->noticesFor('thA'), 'title'));

        $this->post('/appointments/ap1/status', ['status' => 'Cancelled'])->assertRedirect();
        $this->assertContains('Appointment cancelled', array_column($this->noticesFor('thA'), 'title'));
    }

    public function test_therapists_cannot_schedule_or_edit(): void
    {
        $this->appointment('ap1', 'thA');
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Lee'));

        $this->get('/appointments/create')->assertForbidden();
        $this->post('/appointments', $this->form())->assertForbidden();
        $this->get('/appointments/ap1/edit')->assertForbidden();
        $this->put('/appointments/ap1', $this->form())->assertForbidden();
        $this->post('/appointments/ap1/status', ['status' => 'Cancelled'])->assertForbidden();
        $this->delete('/appointments/ap1')->assertForbidden();

        $this->assertSame('Upcoming', $this->docs['appointments/ap1']['status']);
    }

    public function test_a_therapist_sees_their_own_schedule_with_a_request_form_but_not_others(): void
    {
        $this->appointment('mine', 'thA', ['patient' => 'Kesh Mine']);
        $this->appointment('theirs', 'thB', ['patient' => 'Other Patient']);
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Lee'));

        $this->get('/appointments')->assertOk()
            ->assertSee('Kesh Mine')
            ->assertDontSee('Other Patient')
            ->assertDontSee('Schedule Appointment');

        $this->get('/appointments/mine')->assertOk()
            ->assertSee('Request a change')
            ->assertDontSee('/appointments/mine/edit', false);

        $this->get('/appointments/theirs')->assertNotFound();
    }

    public function test_admins_do_not_see_the_request_form(): void
    {
        $this->appointment('ap1', 'thA');
        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'))->get('/appointments/ap1')->assertOk()
            ->assertDontSee('Request a change')
            ->assertSee('/appointments/ap1/edit', false);
    }

    public function test_a_therapist_request_goes_to_every_administrator(): void
    {
        $this->staff('admin', 'adm2', 'Clinic Manager');
        $this->appointment('ap1', 'thA');
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Lee'));

        $this->post('/appointments/ap1/request', ['message' => 'Patient needs to move to 2:00 PM.'])
            ->assertRedirect()
            ->assertSessionHas('success');

        foreach (['adm1', 'adm2'] as $admin) {
            $notices = $this->noticesFor($admin);
            $this->assertCount(1, $notices, $admin);
            $notice = array_values($notices)[0];
            $this->assertSame('request', $notice['type']);
            $this->assertSame('Schedule change requested', $notice['title']);
            $this->assertStringContainsString('Patient needs to move to 2:00 PM.', $notice['body']);
            $this->assertSame('ap1', $notice['appointmentId']);
            $this->assertSame('Dr. Lee', $notice['fromName']);
        }
        $this->assertSame([], $this->noticesFor('thA'));
    }

    public function test_a_request_needs_a_real_reason(): void
    {
        $this->appointment('ap1', 'thA');
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Lee'));

        $this->post('/appointments/ap1/request', ['message' => 'no'])->assertSessionHasErrors('message');
        $this->assertSame([], $this->docsLike('staffNotices/*'));
    }

    public function test_a_therapist_cannot_request_a_change_to_someone_elses_appointment(): void
    {
        $this->appointment('theirs', 'thB');
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Lee'));

        $this->post('/appointments/theirs/request', ['message' => 'Please move this one.'])->assertNotFound();
        $this->assertSame([], $this->docsLike('staffNotices/*'));
    }

    public function test_the_messages_tab_shows_the_unread_count(): void
    {
        $this->patientDoc('pAnna', ['name' => 'Anna Cruz', 'therapistId' => 'thA']);
        $this->patientDoc('pBen', ['name' => 'Ben Cruz', 'therapistId' => 'thB']);
        $this->docs['patients/pAnna/threads/therapist'] = ['unreadForStaff' => 2];
        $this->docs['patients/pBen/threads/clinic'] = ['unreadForStaff' => 1];

        // The therapist only counts their own patient's messages.
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Lee'))->get('/dashboard')->assertOk()
            ->assertSee('aria-label="2 unread messages"', false);

        // The clinic thread belongs to administrators: they see every patient's.
        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'))->get('/dashboard')->assertOk()
            ->assertSee('aria-label="1 unread messages"', false);
    }

    public function test_opening_a_chat_clears_the_badge_straight_away(): void
    {
        $this->patientDoc('pAnna', ['name' => 'Anna Cruz', 'therapistId' => 'thA']);
        $this->docs['patients/pAnna/threads/therapist'] = ['unreadForStaff' => 2];
        $therapist = $this->staff('therapist', 'thA', 'Dr. Lee');

        // Fills the 30-second cache with the current count.
        $this->actingAs($therapist)->get('/dashboard')->assertSee('aria-label="2 unread messages"', false);

        $this->get('/messages/pAnna')->assertOk();
        $this->assertSame(0, $this->docs['patients/pAnna/threads/therapist']['unreadForStaff']);

        $this->get('/dashboard')->assertOk()->assertDontSee('rounded-pill bg-danger ms-2', false);
    }

    public function test_no_badge_when_everything_is_read(): void
    {
        $this->patientDoc('pAnna', ['name' => 'Anna Cruz', 'therapistId' => 'thA']);
        $this->docs['patients/pAnna/threads/therapist'] = ['unreadForStaff' => 0];

        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Lee'))->get('/dashboard')->assertOk()
            ->assertDontSee('rounded-pill bg-danger ms-2', false);
    }
}
