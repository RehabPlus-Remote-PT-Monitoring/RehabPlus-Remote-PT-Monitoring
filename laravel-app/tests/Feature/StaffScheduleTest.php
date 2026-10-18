<?php

namespace Tests\Feature;

use Illuminate\Support\Carbon;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** Shifts and time off live in Firestore; the staff list comes from Firebase accounts. */
class StaffScheduleTest extends TestCase
{
    use FakeFirebase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->actingAs($this->staff('admin', 'adm', 'Admin'));
        $this->staff('therapist', 'th1', 'Dr. Real Therapist');
    }

    public function test_schedule_lists_real_staff_without_patients_or_disabled_accounts(): void
    {
        $this->patientDoc('pat1', ['name' => 'Some Patient']);
        $this->staff('staff', 'gone', 'Former Staffer');
        $this->docs['users/gone']['active'] = false;

        $this->get('/schedule')
            ->assertOk()
            ->assertSee('Dr. Real Therapist')
            ->assertDontSee('Some Patient')
            ->assertDontSee('Former Staffer')
            ->assertDontSee('Dr. Sarah Mitchell');
    }

    public function test_shift_can_be_added_and_shows_today(): void
    {
        $today = Carbon::today()->format('l');

        $this->post('/schedule/save', [
            'staff' => 'Dr. Real Therapist',
            'role' => 'Therapist',
            'day' => $today,
            'shift' => '08:00 - 15:00',
            'room' => 'Room 3',
        ])->assertRedirect('/schedule');

        $shifts = array_values($this->docsLike('staffShifts/*'));
        $this->assertCount(1, $shifts);
        $this->assertSame(['staff' => 'Dr. Real Therapist', 'role' => 'Therapist', 'day' => $today, 'shift' => '08:00 - 15:00', 'room' => 'Room 3'],
            array_intersect_key($shifts[0], array_flip(['staff', 'role', 'day', 'shift', 'room'])));
        $this->assertArrayHasKey('createdAt', $shifts[0]);

        $this->get('/schedule')->assertOk()->assertSee('08:00 - 15:00')->assertSee('Available');
    }

    public function test_overlapping_shift_in_same_room_is_rejected(): void
    {
        $this->docs['staffShifts/s1'] = ['staff' => 'A', 'role' => 'Therapist', 'day' => 'Monday', 'shift' => '08:00 - 12:00', 'room' => 'Room 1'];

        $this->post('/schedule/save', [
            'staff' => 'B',
            'role' => 'Therapist',
            'day' => 'Monday',
            'shift' => '10:00 - 14:00',
            'room' => 'Room 1',
        ])->assertRedirect('/schedule')->assertSessionHas('error');

        $this->assertCount(1, $this->docsLike('staffShifts/*'));
    }

    public function test_time_off_marks_staff_on_leave(): void
    {
        $this->post('/schedule/time-off/save', [
            'staff' => 'Dr. Real Therapist',
            'date' => Carbon::today()->toDateString(),
            'time_off_type' => 'Full day',
            'reason' => 'Medical leave',
        ])->assertRedirect('/schedule');

        $off = array_values($this->docsLike('staffTimeOff/*'))[0];
        $this->assertSame('Dr. Real Therapist', $off['staff']);
        $this->assertSame('Medical leave', $off['reason']);
        $this->assertSame(Carbon::today()->toDateString(), $off['date']);
        $this->get('/schedule')->assertOk()->assertSee('On Leave');
    }
}
