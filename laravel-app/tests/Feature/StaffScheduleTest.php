<?php

namespace Tests\Feature;

use App\Models\StaffSchedule;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

class StaffScheduleTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->actingAs(User::factory()->create(['name' => 'Admin', 'role' => 'superadmin', 'is_active' => true]));
    }

    public function test_schedule_lists_real_staff_without_demo_therapists(): void
    {
        User::factory()->create(['name' => 'Dr. Real Therapist', 'role' => 'therapist']);
        User::factory()->create(['name' => 'Some Patient', 'role' => 'patient']);

        $this->get('/schedule')
            ->assertOk()
            ->assertSee('Dr. Real Therapist')
            ->assertDontSee('Some Patient')
            ->assertDontSee('Dr. Sarah Mitchell');
    }

    public function test_shift_can_be_added_and_shows_today(): void
    {
        User::factory()->create(['name' => 'Dr. Real Therapist', 'role' => 'therapist']);
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
        User::factory()->create(['name' => 'Dr. Real Therapist', 'role' => 'therapist']);

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
