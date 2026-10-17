<?php

namespace Tests\Feature;

use App\Models\InventoryItem;
use App\Models\PaymentRecord;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** Pages of the original dashboard still load; billing/inventory still use SQL. */
class RehabPlusConversionTest extends TestCase
{
    use FakeFirebase, RefreshDatabase;

    public function test_admin_management_pages_load(): void
    {
        $this->actingAs($this->staff('admin', 'adm', 'Super Admin'));

        $pages = [
            '/dashboard' => 'RehabPlus Dashboard',
            '/reports' => 'Reports & Analytics',
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
        $this->actingAs($this->staff('staff'))->get('/dashboard')->assertOk()
            ->assertDontSee('Therapy Notes &amp; Care Plans', false)
            ->assertDontSee('Staff Accounts')
            ->assertSee('Front Desk Staff');

        $this->actingAs($this->staff('therapist'))->get('/dashboard')->assertOk()
            ->assertSee('Therapy Notes &amp; Care Plans', false)
            ->assertDontSee('Staff Accounts');
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

    public function test_payment_record_can_be_created(): void
    {
        $this->actingAs($this->staff('admin'));

        $this->post('/billing', [
            'patient' => 'Maria Santos',
            'session' => 'Physical Therapy',
            'fee' => '1500.00',
            'status' => 'Paid',
            'date' => '2026-10-09',
        ])->assertRedirect('/billing');

        $this->assertDatabaseHas('payment_records', ['patient' => 'Maria Santos', 'fee' => '1500.00', 'status' => 'Paid']);
    }

    public function test_payment_status_can_be_updated_and_deleted(): void
    {
        $this->actingAs($this->staff('admin'));
        $payment = PaymentRecord::create([
            'patient' => 'Maria Santos', 'session' => 'Physical Therapy', 'fee' => '1500.00', 'status' => 'Pending', 'date' => '2026-10-09',
        ]);

        $this->patch("/billing/{$payment->id}/status", ['status' => 'Paid'])->assertRedirect('/billing');
        $this->assertDatabaseHas('payment_records', ['id' => $payment->id, 'status' => 'Paid']);
        $this->patch("/billing/{$payment->id}/status", ['status' => 'Refunded'])->assertSessionHasErrors('status');

        $this->delete("/billing/{$payment->id}")->assertRedirect('/billing');
        $this->assertDatabaseMissing('payment_records', ['id' => $payment->id]);
    }

    public function test_inventory_item_can_be_created_and_status_changed(): void
    {
        $this->actingAs($this->staff('admin'));

        $this->post('/inventory', [
            'item' => 'Resistance Band', 'category' => 'Equipment', 'stock' => 20, 'reorder' => 10, 'status' => 'Healthy',
        ])->assertRedirect('/inventory');
        $item = InventoryItem::firstOrFail();

        $this->patch("/inventory/{$item->id}/status", ['status' => 'Critical'])->assertRedirect('/inventory');
        $this->assertDatabaseHas('inventory_items', ['id' => $item->id, 'status' => 'Critical', 'stock' => 20]);
        $this->patch("/inventory/{$item->id}/status", ['status' => 'Unknown'])->assertSessionHasErrors('status');
    }
}
