<?php

namespace Tests\Feature;

use App\Models\StaffSchedule;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** The schedule is still on SQL; its staff list comes from Firebase accounts. */
class StaffScheduleTest extends TestCase
{
    use FakeFirebase, RefreshDatabase;

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

        $this->assertDatabaseHas('staff_schedules', ['staff' => 'Dr. Real Therapist', 'day' => $today, 'room' => 'Room 3']);

        $this->get('/schedule')->assertOk()->assertSee('08:00 - 15:00')->assertSee('Available');
    }

    public function test_overlapping_shift_in_same_room_is_rejected(): void
    {
        StaffSchedule::create(['staff' => 'A', 'role' => 'Therapist', 'day' => 'Monday', 'shift' => '08:00 - 12:00', 'room' => 'Room 1']);

        $this->post('/schedule/save', [
            'staff' => 'B',
            'role' => 'Therapist',
            'day' => 'Monday',
            'shift' => '10:00 - 14:00',
            'room' => 'Room 1',
        ])->assertRedirect('/schedule')->assertSessionHas('error');

        $this->assertDatabaseCount('staff_schedules', 1);
    }

    public function test_time_off_marks_staff_on_leave(): void
    {
        $this->post('/schedule/time-off/save', [
            'staff' => 'Dr. Real Therapist',
            'date' => Carbon::today()->toDateString(),
            'time_off_type' => 'Full day',
            'reason' => 'Medical leave',
        ])->assertRedirect('/schedule');

        $this->assertDatabaseHas('staff_time_offs', ['staff' => 'Dr. Real Therapist', 'reason' => 'Medical leave']);
        $this->get('/schedule')->assertOk()->assertSee('On Leave');
    }
}
