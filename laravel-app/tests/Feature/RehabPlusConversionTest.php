<?php

namespace Tests\Feature;

use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** Pages of the original dashboard still load; billing/inventory live in Firestore. */
class RehabPlusConversionTest extends TestCase
{
    use FakeFirebase;

    public function test_admin_management_pages_load(): void
    {
        $this->actingAs($this->staff('admin', 'adm', 'Super Admin'));

        $pages = [
            '/dashboard' => 'RehabPlus Dashboard',
            '/analytics' => 'Reports & Analytics',
            '/patients' => 'Patients',
            '/patients/create' => 'Add Patient',
            '/messages' => 'Messages',
            '/appointments' => 'Appointments',
            '/appointments/create' => 'Appointment',
            '/billing' => 'Billing and Payment Records',
            '/inventory' => 'Inventory and Supplies',
            '/schedule' => 'Staff Schedule',
            '/notes' => 'Therapy Notes & Care Plans',
            '/assessments' => 'Assessments & Goals',
            '/users' => 'Staff Accounts',
            '/users/create' => 'New Staff Account',
        ];

        foreach ($pages as $path => $heading) {
            $this->get($path)
                ->assertOk()
                ->assertSee($heading)
                ->assertSee('RehabPlus');
        }
    }

    public function test_sidebar_matches_role(): void
    {
        $this->actingAs($this->staff('therapist'))->get('/dashboard')->assertOk()
            ->assertSee('Therapy Notes &amp; Care Plans', false)
            ->assertDontSee('Staff Accounts');

        $this->actingAs($this->staff('admin'))->get('/dashboard')->assertOk()
            ->assertSee('Therapy Notes &amp; Care Plans', false)
            ->assertSee('Staff Accounts');
    }

    public function test_appointment_form_lists_firebase_therapists(): void
    {
        $this->staff('therapist', 'th1', 'Dr. Lee');

        $this->actingAs($this->staff('admin'))->get('/appointments/create')->assertOk()->assertSee('Dr. Lee');
    }

    public function test_billing_page_uses_pesos(): void
    {
        $this->actingAs($this->staff('admin'))->get('/billing')->assertOk()->assertSee('₱0.00');
    }

    public function test_billing_form_only_offers_patients_with_appointments(): void
    {
        $this->patientDoc('pat1', ['name' => 'Maria Santos']);
        $this->patientDoc('pat2', ['name' => 'No Appointments']);
        $this->docs['appointments/a1'] = ['patient' => 'Maria Santos', 'session' => 'Physical Therapy'];
        $this->docs['appointments/a2'] = ['patient' => ' maria santos ', 'session' => 'physical therapy'];
        $this->docs['appointments/a3'] = ['patient' => 'Maria Santos', 'session' => 'Massage'];
        $this->docs['appointments/a4'] = ['patient' => 'Typed Walk-in', 'session' => 'Assessment'];

        $response = $this->actingAs($this->staff('admin'))->get('/billing')->assertOk()
            ->assertDontSee('No Appointments');

        $this->assertSame([
            ['name' => 'Maria Santos', 'sessions' => ['Massage', 'Physical Therapy']],
            ['name' => 'Typed Walk-in', 'sessions' => ['Assessment']],
        ], $response->viewData('billablePatients'));
    }

    public function test_therapists_only_get_patients_from_their_own_appointments(): void
    {
        $this->docs['appointments/a1'] = ['patient' => 'Mine', 'session' => 'Massage', 'therapistId' => 'th1'];
        $this->docs['appointments/a2'] = ['patient' => 'Theirs', 'session' => 'Massage', 'therapistId' => 'th2'];

        $response = $this->actingAs($this->staff('therapist', 'th1'))->get('/billing')->assertOk();

        $this->assertSame([['name' => 'Mine', 'sessions' => ['Massage']]], $response->viewData('billablePatients'));

        $this->post('/billing', ['patient' => 'Theirs', 'session' => 'Massage', 'fee' => '100', 'status' => 'Paid', 'date' => '2026-10-09'])
            ->assertSessionHasErrors('patient');
    }

    public function test_billing_only_accepts_a_patient_with_an_appointment_and_their_own_session(): void
    {
        $this->patientDoc('pat1', ['name' => 'No Appointments']);
        $this->docs['appointments/a1'] = ['patient' => 'Maria Santos', 'session' => 'Physical Therapy'];
        $this->docs['appointments/a2'] = ['patient' => 'Juan Cruz', 'session' => 'Massage'];
        $this->actingAs($this->staff('admin'));
        $payment = ['fee' => '100', 'status' => 'Paid', 'date' => '2026-10-09'];

        $this->post('/billing', ['patient' => 'No Appointments', 'session' => 'Physical Therapy'] + $payment)
            ->assertSessionHasErrors('patient');
        $this->post('/billing', ['patient' => 'Juan Cruz', 'session' => 'Physical Therapy'] + $payment)
            ->assertSessionHasErrors('session');

        $this->assertSame([], $this->docsLike('payments/*'));
    }

    public function test_payment_record_can_be_created(): void
    {
        $this->actingAs($this->staff('admin'));
        $this->docs['appointments/a1'] = ['patient' => 'Maria Santos', 'session' => 'Physical Therapy'];

        $this->post('/billing', [
            'patient' => 'Maria Santos',
            'session' => 'Physical Therapy',
            'fee' => '1500.00',
            'status' => 'Paid',
            'date' => '2026-10-09',
        ])->assertRedirect('/billing');

        $payment = array_values($this->docsLike('payments/*'))[0];
        $this->assertSame('Maria Santos', $payment['patient']);
        $this->assertSame(1500.0, $payment['fee']);
        $this->assertSame('Paid', $payment['status']);
        $this->assertSame('2026-10-09', $payment['date']);

        $this->get('/billing')->assertOk()->assertSee('Maria Santos')->assertSee('1500.00')->assertSee('₱1,500.00');
    }

    public function test_payment_status_can_be_updated_and_deleted(): void
    {
        $this->actingAs($this->staff('admin'));
        $this->docs['payments/pay1'] = ['patient' => 'Maria Santos', 'session' => 'Physical Therapy', 'fee' => 1500.0, 'status' => 'Pending', 'date' => '2026-10-09'];

        $this->patch('/billing/pay1/status', ['status' => 'Paid'])->assertRedirect('/billing');
        $this->assertSame('Paid', $this->docs['payments/pay1']['status']);
        $this->assertSame('Maria Santos', $this->docs['payments/pay1']['patient']);
        $this->patch('/billing/pay1/status', ['status' => 'Refunded'])->assertSessionHasErrors('status');

        $this->delete('/billing/pay1')->assertRedirect('/billing');
        $this->assertArrayNotHasKey('payments/pay1', $this->docs);
    }

    public function test_missing_or_malformed_payment_ids_are_404(): void
    {
        $this->actingAs($this->staff('admin'));

        $this->patch('/billing/nope/status', ['status' => 'Paid'])->assertNotFound();
        $this->delete('/billing/a..b')->assertNotFound();
        $this->assertSame([], $this->commits);
    }

    public function test_inventory_item_can_be_created_and_status_changed(): void
    {
        $this->actingAs($this->staff('admin'));

        $this->post('/inventory', [
            'item' => 'Resistance Band', 'category' => 'Equipment', 'stock' => 20, 'reorder' => 10, 'status' => 'In Stock',
        ])->assertRedirect('/inventory');
        $path = array_key_first($this->docsLike('inventory/*'));
        $id = explode('/', $path)[1];
        $this->assertSame(20, $this->docs[$path]['stock']);

        $this->patch("/inventory/{$id}/status", ['status' => 'Out of Stock'])->assertRedirect('/inventory');
        $this->assertSame('Out of Stock', $this->docs[$path]['status']);
        $this->assertSame(20, $this->docs[$path]['stock']);
        $this->patch("/inventory/{$id}/status", ['status' => 'Unknown'])->assertSessionHasErrors('status');
        $this->patch("/inventory/{$id}/status", ['status' => 'Healthy'])->assertSessionHasErrors('status');

        $this->get('/inventory')->assertOk()->assertSee('Resistance Band');
        $this->get("/inventory/{$id}/edit")->assertOk()->assertSee('Save changes');

        $this->put("/inventory/{$id}", [
            'item' => 'Resistance Band (heavy)', 'category' => 'Equipment', 'stock' => 5, 'reorder' => 10, 'status' => 'Low Stock',
        ])->assertRedirect('/inventory');
        $this->assertSame('Resistance Band (heavy)', $this->docs[$path]['item']);
        $this->get('/inventory')->assertOk()->assertSee('1 orders'); // stock 5 <= reorder 10

        $this->delete("/inventory/{$id}")->assertRedirect('/inventory');
        $this->assertSame([], $this->docsLike('inventory/*'));
        $this->get('/inventory/missing/edit')->assertNotFound();
    }

    public function test_status_list_is_the_same_in_the_form_and_each_item_and_old_health_words_are_shown_as_stock_status(): void
    {
        $this->actingAs($this->staff('admin'));
        $this->docs['inventory/old1'] = ['item' => 'Gauze', 'category' => 'Supplies', 'stock' => 3, 'reorder' => 5, 'status' => 'Critical'];

        $html = $this->get('/inventory')->assertOk()
            ->assertSee('Out of Stock')
            ->assertSee('1 items')
            ->assertDontSee('>Critical<', false)
            ->assertDontSee('>Healthy<', false)
            ->getContent();

        // One option per status in the Add item form and one in the Actions list of the single item.
        foreach (['In Stock', 'Low Stock', 'Out of Stock'] as $status) {
            $this->assertSame(2, substr_count($html, '<option value="'.$status.'"'), $status);
        }
    }
}
