<?php

namespace Tests\Feature;

use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Http;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** Appointments are stored in the Firestore `appointments` collection. */
class AppointmentTest extends TestCase
{
    use FakeFirebase;

    private function form(array $overrides = []): array
    {
        return $overrides + [
            'patient' => 'Emily Johnson',
            'therapist' => 'Dr. Lee',
            'patient_condition' => 'Knee rehab',
            'contact_country' => 'PH',
            'contact' => '9175550101',
            'date' => '2026-10-20',
            'time' => '09:30',
            'session' => 'Mobility Session',
            'notes' => 'Focus on flexion.',
            'status' => 'Upcoming',
        ];
    }

    public function test_appointment_is_created_listed_and_shown(): void
    {
        $this->actingAs($this->staff('admin'));

        $this->post('/appointments', $this->form())->assertRedirect('/appointments')->assertSessionHas('success');

        $path = array_key_first($this->docsLike('appointments/*'));
        $id = explode('/', $path)[1];
        $doc = $this->docs[$path];
        $this->assertSame('Emily Johnson', $doc['patient']);
        $this->assertSame('2026-10-20', $doc['date']);
        $this->assertSame('09:30', $doc['time']);
        $this->assertSame('+639175550101', $doc['contact']);
        $this->assertNull($doc['completed_at']);
        $this->assertArrayHasKey('createdAt', $doc);

        $this->get('/appointments')->assertOk()->assertSee('Emily Johnson')->assertSee('Oct 20, 2026');
        $this->get("/appointments/{$id}")->assertOk()->assertSee('Knee rehab')->assertSee('9:30 AM');
        $this->get("/appointments/{$id}/edit")->assertOk()->assertSee('Update Appointment')->assertSee('9175550101');
    }

    public function test_patient_name_offers_active_patients_and_still_accepts_typing(): void
    {
        $this->patientDoc('pOne', ['name' => 'Olive One', 'condition' => 'ACL', 'therapistId' => 'thA']);
        $this->patientDoc('pOld', ['name' => 'Otto Archived', 'therapistId' => 'thA', 'archived' => true]);
        $this->patientDoc('pTwo', ['name' => 'Tom Two', 'therapistId' => 'thB']);
        $this->staff('therapist', 'thA', 'Dr. Ana');

        $this->actingAs($this->staff('admin'))->get('/appointments/create')
            ->assertOk()
            ->assertSee('data-patient-picker', false)
            ->assertSee('data-patient-option data-name="Olive One"', false)
            ->assertSee('data-patient-option data-name="Tom Two"', false)
            ->assertDontSee('Otto Archived')
            ->assertSee('name="patient"', false);

        $this->actingAs($this->staff('therapist', 'thA'))->get('/appointments/create')
            ->assertOk()
            ->assertSee('Olive One')
            ->assertDontSee('Tom Two');
    }

    public function test_cancelled_is_only_offered_when_editing(): void
    {
        $this->actingAs($this->staff('admin'));
        $this->get('/appointments/create')->assertOk()->assertDontSee('value="Cancelled"', false);

        $this->docs['appointments/ap1'] = $this->form(['status' => 'Upcoming']);
        $this->get('/appointments/ap1/edit')->assertOk()->assertSee('value="Cancelled"', false);
    }

    public function test_contact_is_checked_against_the_chosen_country(): void
    {
        $this->actingAs($this->staff('admin'));

        $this->post('/appointments', $this->form(['contact' => 'call mom']))
            ->assertSessionHasErrors('contact');
        $this->post('/appointments', $this->form(['contact_country' => 'AU', 'contact' => '1234']))
            ->assertSessionHasErrors('contact');
        $this->assertSame([], $this->commits);

        $this->post('/appointments', $this->form(['contact_country' => 'AU', 'contact' => '412345678']))
            ->assertRedirect('/appointments');
        $this->assertSame('+61412345678', $this->docs[array_key_first($this->docsLike('appointments/*'))]['contact']);
    }

    public function test_status_change_stamps_completion_and_counts_today(): void
    {
        $this->actingAs($this->staff('admin'));
        $this->docs['appointments/ap1'] = $this->form(['date' => now()->toDateString(), 'completed_at' => null]);

        $this->post('/appointments/ap1/status', ['status' => 'Completed'])->assertRedirect('/appointments');
        $this->assertSame('Completed', $this->docs['appointments/ap1']['status']);
        $this->assertInstanceOf(CarbonImmutable::class, $this->docs['appointments/ap1']['completed_at']);
        $this->assertSame('Emily Johnson', $this->docs['appointments/ap1']['patient']);

        $this->post('/appointments/ap1/status', ['status' => 'Bogus'])->assertSessionHas('error');
        $this->assertSame('Completed', $this->docs['appointments/ap1']['status']);

        $this->post('/appointments/ap1/status', ['status' => 'Cancelled']);
        $this->assertNull($this->docs['appointments/ap1']['completed_at']);
    }

    public function test_update_keeps_original_completion_time(): void
    {
        $this->actingAs($this->staff('admin'));
        $done = CarbonImmutable::parse('2026-10-01 10:00:00');
        $this->docs['appointments/ap1'] = $this->form(['status' => 'Completed', 'completed_at' => $done]);

        $this->put('/appointments/ap1', $this->form(['status' => 'Completed', 'notes' => 'Edited']))->assertRedirect('/appointments');

        $this->assertSame('Edited', $this->docs['appointments/ap1']['notes']);
        $this->assertTrue($done->equalTo($this->docs['appointments/ap1']['completed_at']));
    }

    public function test_delete_and_missing_ids(): void
    {
        $this->actingAs($this->staff('admin'));
        $this->docs['appointments/ap1'] = $this->form();

        $this->delete('/appointments/ap1')->assertRedirect('/appointments');
        $this->assertArrayNotHasKey('appointments/ap1', $this->docs);

        $this->get('/appointments/ap1')->assertNotFound();
        $this->put('/appointments/nope', $this->form())->assertNotFound();
        $this->get('/appointments/bad.id')->assertNotFound();
        $this->assertSame([], $this->commits);
    }

    public function test_firestore_outage_shows_friendly_page(): void
    {
        $this->actingAs($this->staff('admin'));
        Http::fake(fn () => Http::failedConnection());

        $this->get('/appointments')->assertStatus(503)->assertSee('Could not reach Firebase');
    }
}
