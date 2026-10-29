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
            ->assertSee('Dr. Real Therapist (Physical Therapist)')
            ->assertDontSee('Some Patient')
            ->assertDontSee('Former Staffer')
            ->assertDontSee('Dr. Sarah Mitchell');
    }

    public function test_shift_can_be_added_and_shows_today(): void
    {
        $today = Carbon::today()->format('l');

        $this->post('/schedule/save', [
            'staff_id' => 'th1',
            'day' => $today,
            'shift' => '08:00 - 15:00',
            'room' => 'Room 3',
        ])->assertRedirect('/schedule');

        $shifts = array_values($this->docsLike('staffShifts/*'));
        $this->assertCount(1, $shifts);
        $this->assertSame(['staffId' => 'th1', 'staff' => 'Dr. Real Therapist', 'role' => 'therapist', 'day' => $today, 'shift' => '08:00 - 15:00', 'room' => 'Room 3'],
            array_intersect_key($shifts[0], array_flip(['staffId', 'staff', 'role', 'day', 'shift', 'room'])));
        $this->assertArrayHasKey('createdAt', $shifts[0]);

        $this->get('/schedule')->assertOk()->assertSee('08:00 - 15:00')->assertSee('Available');
    }

    public function test_role_comes_from_the_account_not_from_the_form(): void
    {
        // A client that sends its own role is ignored: the stored role is the account's.
        $this->post('/schedule/save', [
            'staff_id' => 'th1',
            'role' => 'admin',
            'day' => 'Monday',
            'shift' => '08:00 - 12:00',
            'room' => 'Room 4',
        ])->assertRedirect('/schedule');

        $shift = array_values($this->docsLike('staffShifts/*'))[0];
        $this->assertSame('therapist', $shift['role']);
    }

    public function test_overlapping_shift_in_same_room_is_rejected(): void
    {
        $this->staff('therapist', 'thA', 'A');
        $this->staff('staff', 'stB', 'B');
        $this->docs['staffShifts/s1'] = ['staffId' => 'thA', 'staff' => 'A', 'role' => 'therapist', 'day' => 'Monday', 'shift' => '08:00 - 12:00', 'room' => 'Room 1'];

        $this->post('/schedule/save', [
            'staff_id' => 'stB',
            'day' => 'Monday',
            'shift' => '10:00 - 14:00',
            'room' => 'Room 1',
        ])->assertRedirect('/schedule')->assertSessionHas('error', fn (string $e) => str_contains($e, 'conflict'));

        $this->assertCount(1, $this->docsLike('staffShifts/*'));
    }

    public function test_only_therapists_and_front_desk_are_listed_never_admins(): void
    {
        $this->staff('admin', 'adm2', 'Second Clinic Admin');
        $this->staff('staff', 'fd1', 'Front Desk Person');
        // An old shift saved under an admin's name doesn't put them back on the schedule.
        $this->docs['staffShifts/old'] = ['staff' => 'Second Clinic Admin', 'role' => 'Admin', 'day' => Carbon::today()->format('l'), 'shift' => '08:00 - 12:00', 'room' => 'Room 9'];

        $this->get('/schedule')
            ->assertOk()
            ->assertSee('Dr. Real Therapist')
            ->assertSee('Front Desk Person')
            ->assertDontSee('Second Clinic Admin')
            ->assertDontSee('Room 9')
            ->assertViewHas('todayShifts', 0);
    }

    public function test_admins_and_unknown_accounts_cannot_be_given_shifts_or_time_off(): void
    {
        $this->staff('admin', 'adm2', 'Second Clinic Admin');

        foreach (['adm2', 'adm', 'nobody-at-all'] as $uid) {
            $this->post('/schedule/save', [
                'staff_id' => $uid,
                'day' => 'Monday',
                'shift' => '08:00 - 12:00',
                'room' => 'Room 1',
            ])->assertRedirect('/schedule')->assertSessionHas('error', fn (string $e) => str_contains($e, 'Only active therapists'));

            $this->post('/schedule/time-off/save', [
                'staff_id' => $uid,
                'date' => Carbon::today()->toDateString(),
                'reason' => 'Leave',
            ])->assertRedirect('/schedule')->assertSessionHas('error');
        }

        $this->assertCount(0, $this->docsLike('staffShifts/*'));
        $this->assertCount(0, $this->docsLike('staffTimeOff/*'));
    }

    public function test_two_accounts_with_the_same_name_are_two_rows_with_one_role_each(): void
    {
        $this->staff('staff', 'fd2', 'Dr. Real Therapist');

        $this->get('/schedule')
            ->assertOk()
            ->assertViewHas('staffDirectory', fn (array $dir) => collect($dir)->pluck('roleLabel', 'uid')->sortKeys()->all()
                === ['fd2' => 'Front Desk Staff', 'th1' => 'Physical Therapist']);
    }

    public function test_staff_member_dropdown_and_time_off_dropdown_show_the_same_name_and_role(): void
    {
        $this->get('/schedule')
            ->assertOk()
            ->assertSee('value="th1"', false)
            ->assertSee('Dr. Real Therapist (Physical Therapist)')
            ->assertDontSee('name="role"', false);
    }

    public function test_front_desk_staff_can_be_given_a_shift(): void
    {
        $this->staff('staff', 'fd1', 'Front Desk Person');

        $this->post('/schedule/save', [
            'staff_id' => 'fd1',
            'day' => 'Tuesday',
            'shift' => '09:00 - 17:00',
            'room' => 'Reception',
        ])->assertRedirect('/schedule')->assertSessionMissing('error');

        $shift = array_values($this->docsLike('staffShifts/*'))[0];
        $this->assertSame('staff', $shift['role']);
        $this->assertCount(1, $this->docsLike('staffShifts/*'));
    }

    public function test_time_off_marks_staff_on_leave(): void
    {
        $this->post('/schedule/time-off/save', [
            'staff_id' => 'th1',
            'date' => Carbon::today()->toDateString(),
            'time_off_type' => 'Full day',
            'reason' => 'Medical leave',
        ])->assertRedirect('/schedule');

        $off = array_values($this->docsLike('staffTimeOff/*'))[0];
        $this->assertSame('th1', $off['staffId']);
        $this->assertSame('Dr. Real Therapist', $off['staff']);
        $this->assertSame('Medical leave', $off['reason']);
        $this->assertSame(Carbon::today()->toDateString(), $off['date']);
        $this->get('/schedule')->assertOk()->assertSee('On Leave');
    }

    public function test_older_entries_saved_by_name_count_only_for_a_unique_name(): void
    {
        $this->docs['staffShifts/legacy'] = ['staff' => 'Dr. Real Therapist', 'day' => Carbon::today()->format('l'), 'shift' => '08:00 - 12:00', 'room' => 'Room 5'];

        $this->get('/schedule')->assertOk()->assertSee('Room 5')->assertViewHas('staffAvailability', fn (array $a) => $a['th1'] === 'Available');

        // With a second account under the same name the old entry can't be tied to either one.
        $this->staff('staff', 'fd2', 'Dr. Real Therapist');
        $this->get('/schedule')->assertOk()->assertViewHas('staffAvailability', fn (array $a) => $a['th1'] === 'Unavailable' && $a['fd2'] === 'Unavailable');
    }
}
