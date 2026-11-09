<?php

namespace Tests\Feature;

use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** Billing and payment records: every staff member can view the page; only administrators record, change, or delete. */
class BillingTest extends TestCase
{
    use FakeFirebase;

    public function test_therapists_can_view_billing_but_not_record_change_or_delete_payments(): void
    {
        $therapist = $this->staff('therapist', 'thA', 'Dr. Ana');

        $this->actingAs($therapist)->get('/billing')->assertOk()
            ->assertDontSee('Add payment record')
            ->assertDontSee('data-confirm-if-field')
            ->assertDontSee('data-print');

        $this->actingAs($therapist)->post('/billing', ['patient' => 'Olive One', 'amount' => 500])->assertForbidden();
        $this->actingAs($therapist)->patch('/billing/pay1/status', ['status' => 'Paid'])->assertForbidden();
        $this->actingAs($therapist)->delete('/billing/pay1')->assertForbidden();

        $this->assertSame([], $this->commits);
    }

    public function test_a_payment_shows_the_discount_and_tax_it_was_charged_with(): void
    {
        $this->docs['appointments/a1'] = ['patient' => 'Mine', 'session' => 'Massage', 'therapistId' => 'th1'];

        $this->actingAs($this->staff('admin'))->post('/billing', ['patient' => 'Mine', 'session' => 'Massage', 'fee' => '1000', 'discount' => '100', 'tax_rate' => '12', 'status' => 'Pending', 'date' => now()->toDateString()])
            ->assertRedirect('/billing');

        $payment = array_values($this->docsLike('payments/*'))[0];
        $this->assertSame(1000.0, $payment['fee']);
        $this->assertSame(100.0, $payment['discount']);
        $this->assertSame(108.0, $payment['tax']);
        $this->assertSame(1008.0, $payment['total']);

        $this->actingAs($this->staff('admin'))->get('/billing')->assertOk()
            ->assertSee('Discount')->assertSee('Tax (12%)')->assertSee('Total due')->assertSee('0912 854 8156');
    }

    public function test_administrators_can_record_change_and_delete_payments(): void
    {
        $this->actingAs($this->staff('admin'))->get('/billing')->assertOk()
            ->assertSee('Add payment record');
    }
}
