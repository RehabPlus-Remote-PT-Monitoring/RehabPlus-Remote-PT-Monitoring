<?php

namespace Tests\Feature;

use Illuminate\Support\Carbon;
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

    public function test_each_payment_has_its_own_printable_page(): void
    {
        $this->docs['payments/paid1'] = ['patient' => 'Maria Santos', 'session' => 'Massage', 'fee' => 1500.0, 'status' => 'Paid', 'date' => '2026-10-09'];
        $this->docs['payments/open1'] = ['patient' => 'Juan Cruz', 'session' => 'Rehab', 'fee' => 800.0, 'status' => 'Pending', 'date' => '2026-10-08'];

        $this->actingAs($this->staff('admin'))->get('/billing')->assertOk()
            ->assertSee('id="receipt-paid1"', false)
            ->assertSee('data-print-receipt="receipt-paid1"', false)
            ->assertSee('Payment Receipt')
            ->assertSee('Billing Statement')
            ->assertSee('October 9, 2026')
            ->assertSee(config('clinic.name'));
    }

    public function test_the_header_shows_todays_date_in_the_philippines(): void
    {
        // 3:18 AM on Nov 8 in Manila is still Nov 7 in UTC.
        Carbon::setTestNow(Carbon::parse('2026-11-07 19:18:00', 'UTC'));

        try {
            $this->actingAs($this->staff('admin'))->get('/billing')->assertOk()->assertSee('November 8, 2026');
        } finally {
            Carbon::setTestNow();
        }
    }

    public function test_status_edit_form_starts_closed(): void
    {
        $this->docs['payments/pay1'] = ['patient' => 'Maria Santos', 'session' => 'Massage', 'fee' => 100.0, 'status' => 'Pending', 'date' => '2026-10-09'];

        $html = $this->actingAs($this->staff('admin'))->get('/billing')->assertOk()->getContent();

        // Bootstrap's d-flex would override hidden, leaving the form always open.
        $this->assertMatchesRegularExpression('/<form id="status-form-pay1"[^\n]*\shidden>/', $html);
        $this->assertDoesNotMatchRegularExpression('/<form id="status-form-pay1"[^\n]*d-flex/', $html);
    }

    public function test_paid_status_is_final(): void
    {
        $this->docs['payments/paid'] = ['patient' => 'Maria Santos', 'session' => 'Massage', 'fee' => 100.0, 'status' => 'Paid', 'date' => '2026-10-09'];
        $this->docs['payments/open'] = ['patient' => 'Juan Cruz', 'session' => 'Massage', 'fee' => 100.0, 'status' => 'Partial', 'date' => '2026-10-08'];

        $this->actingAs($this->staff('admin'))->get('/billing')->assertOk()
            ->assertDontSee('status-form-paid', false)
            ->assertSee('status-form-open', false);

        $this->from('/billing')->patch('/billing/paid/status', ['status' => 'Pending'])
            ->assertRedirect('/billing')
            ->assertSessionHasErrors('status');
        $this->assertSame('Paid', $this->docs['payments/paid']['status']);

        $this->patch('/billing/open/status', ['status' => 'Pending'])->assertSessionHasNoErrors();
        $this->assertSame('Pending', $this->docs['payments/open']['status']);

        $this->from('/billing')->followingRedirects()->patch('/billing/paid/status', ['status' => 'Pending'])
            ->assertSee('already paid');
    }

    public function test_payment_status_can_be_updated_and_deleted(): void
    {
        $this->actingAs($this->staff('admin'));
        $this->docs['payments/pay1'] = ['patient' => 'Maria Santos', 'session' => 'Physical Therapy', 'fee' => 1500.0, 'status' => 'Pending', 'date' => '2026-10-09'];

        $this->patch('/billing/pay1/status', ['status' => 'Paid'])->assertRedirect('/billing');
        $this->assertSame('Paid', $this->docs['payments/pay1']['status']);
        $this->assertSame('Maria Santos', $this->docs['payments/pay1']['patient']);
        $this->patch('/billing/pay1/status', ['status' => 'Refunded'])->assertSessionHasErrors('status');

        $this->docs['payments/pay2'] = ['patient' => 'Juan Cruz', 'session' => 'Massage', 'fee' => 500.0, 'status' => 'Pending', 'date' => '2026-10-09'];
        $this->delete('/billing/pay2')->assertRedirect('/billing');
        $this->assertArrayNotHasKey('payments/pay2', $this->docs);
    }

    public function test_missing_or_malformed_payment_ids_are_404(): void
    {
        $this->actingAs($this->staff('admin'));

        $this->patch('/billing/nope/status', ['status' => 'Paid'])->assertNotFound();
        $this->delete('/billing/a..b')->assertNotFound();
        $this->assertSame([], $this->commits);
    }

    public function test_stock_and_reorder_are_dropdowns_and_reject_other_values(): void
    {
        $this->actingAs($this->staff('admin'));

        $this->get('/inventory')->assertOk()
            ->assertSee('<select name="stock"', false)
            ->assertSee('<select name="reorder"', false)
            ->assertDontSee('type="number"', false);

        $item = ['item' => 'Bands', 'category' => 'Gear', 'status' => 'In Stock'];
        foreach ([['stock' => 201], ['stock' => -1], ['stock' => 'abc'], ['stock' => 1.5]] as $bad) {
            $this->post('/inventory', $bad + $item)->assertSessionHasErrors('stock');
        }
        $this->post('/inventory', ['stock' => 5, 'reorder' => 9999] + $item)->assertSessionHasErrors('reorder');
        $this->assertSame([], $this->docsLike('inventory/*'));

        $this->post('/inventory', ['stock' => 200, 'reorder' => ''] + $item)->assertSessionHasNoErrors();
        $this->assertNull(array_values($this->docsLike('inventory/*'))[0]['reorder']);
    }

    public function test_editing_an_item_keeps_a_number_above_the_dropdown_limit(): void
    {
        $this->actingAs($this->staff('admin'));
        $this->docs['inventory/big'] = ['item' => 'Gloves', 'category' => 'Supplies', 'stock' => 750, 'reorder' => 300, 'status' => 'In Stock'];

        $this->get('/inventory/big/edit')->assertOk()
            ->assertSee('<option value="750" selected>750</option>', false)
            ->assertSee('<option value="300" selected>300</option>', false);

        $this->put('/inventory/big', ['item' => 'Gloves', 'category' => 'Supplies', 'stock' => 750, 'reorder' => 300, 'status' => 'Low Stock'])
            ->assertSessionHasNoErrors();
        $this->assertSame(750, $this->docs['inventory/big']['stock']);

        $this->put('/inventory/big', ['item' => 'Gloves', 'category' => 'Supplies', 'stock' => 751, 'status' => 'Low Stock'])
            ->assertSessionHasErrors('stock');
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

    public function test_paid_records_cannot_be_deleted(): void
    {
        $this->actingAs($this->staff('admin'));
        $this->docs['payments/paid'] = ['patient' => 'Maria Santos', 'session' => 'Massage', 'fee' => 100.0, 'status' => 'Paid', 'date' => '2026-10-09'];
        $this->docs['payments/open'] = ['patient' => 'Juan Cruz', 'session' => 'Massage', 'fee' => 100.0, 'status' => 'Pending', 'date' => '2026-10-09'];

        $this->get('/billing')->assertOk()
            ->assertDontSee('action="'.route('billing.delete', 'paid').'"', false)
            ->assertSee('action="'.route('billing.delete', 'open').'"', false);

        $this->from('/billing')->followingRedirects()->delete('/billing/paid')->assertSee("already paid, so it can&#039;t be deleted", false);
        $this->assertArrayHasKey('payments/paid', $this->docs);
    }

    public function test_theme_button_has_both_icons_so_the_stylesheet_can_pick_before_paint(): void
    {
        $this->actingAs($this->staff('admin'))->get('/billing')->assertOk()
            ->assertSee('bi-moon-fill theme-icon-light', false)
            ->assertSee('bi-sun-fill theme-icon-dark', false);
    }

    public function test_add_payment_starts_on_pending(): void
    {
        $this->actingAs($this->staff('admin'))->get('/billing')->assertOk()
            ->assertSee('<option value="Pending" selected>Pending</option>', false);
    }

    public function test_marking_paid_asks_first_only_when_paid_is_chosen(): void
    {
        $this->docs['payments/open'] = ['patient' => 'Juan Cruz', 'session' => 'Massage', 'fee' => 100.0, 'status' => 'Pending', 'date' => '2026-10-09'];

        $html = $this->actingAs($this->staff('admin'))->get('/billing')->assertOk()->getContent();

        $this->assertSame(2, substr_count($html, 'data-confirm-if-field="status" data-confirm-if-value="Paid"'));
    }

    public function test_every_date_field_is_calendar_only(): void
    {
        $this->actingAs($this->staff('admin'));
        $this->patientDoc('pat1', ['name' => 'Maria Santos']); // the notes and assessment forms need a patient

        foreach (['/billing', '/notes', '/appointments/create', '/patients/create', '/schedule', '/assessments'] as $page) {
            $html = $this->get($page)->assertOk()->getContent();

            preg_match_all('/<input[^>]*type="date"[^>]*>/', $html, $dates);
            $this->assertNotEmpty($dates[0], $page);
            foreach ($dates[0] as $input) {
                $this->assertStringContainsString('data-calendar-only', $input, $page);
                $this->assertStringContainsString('min="', $input, $page);
                $this->assertStringContainsString('max="', $input, $page);
            }
        }
    }

    public function test_payment_date_cannot_be_random(): void
    {
        $this->actingAs($this->staff('admin'));
        $this->docs['appointments/a1'] = ['patient' => 'Maria Santos', 'session' => 'Massage'];
        $payment = ['patient' => 'Maria Santos', 'session' => 'Massage', 'fee' => '100', 'status' => 'Paid'];

        foreach (['12345', '0002-01-01', '275760-07-05', now()->addYears(2)->toDateString(), now()->subYears(6)->toDateString()] as $date) {
            $this->post('/billing', ['date' => $date] + $payment)->assertSessionHasErrors('date');
        }

        $this->assertSame([], $this->docsLike('payments/*'));
    }
}
