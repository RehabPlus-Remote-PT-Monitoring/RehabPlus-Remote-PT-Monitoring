<?php

namespace Tests\Feature;

use App\Rules\OfficialEmailDomain;
use App\Services\Patient\PatientProgress;
use Carbon\CarbonImmutable;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

class PatientTest extends TestCase
{
    use FakeFirebase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->staff('therapist', 'thA', 'Dr. Ana');
        $this->staff('therapist', 'thB', 'Dr. Ben');
        $this->patientDoc('pOne', ['name' => 'Olive One', 'condition' => 'ACL', 'therapistId' => 'thA', 'therapistName' => 'Dr. Ana']);
        $this->patientDoc('pTwo', ['name' => 'Tom Two', 'condition' => 'Shoulder', 'therapistId' => 'thB', 'therapistName' => 'Dr. Ben']);
        $this->patientDoc('pOld', ['name' => 'Otto Archived', 'therapistId' => 'thA', 'archived' => true]);
    }

    private function newPatient(array $overrides = []): array
    {
        return $overrides + [
            'name' => 'Nina New', 'condition' => 'Ankle sprain', 'email' => 'Nina@RehabPlus.com',
            'password' => 'temp-pass-1', 'password_confirmation' => 'temp-pass-1',
            'phone_country' => 'PH', 'phone' => '9175550101', 'dob' => '1990-05-14',
            'medical_summary' => 'Inversion sprain', 'therapy_plan' => 'Balance work',
        ];
    }

    public function test_archived_toggle_sits_in_the_header_beside_add_patient(): void
    {
        $this->actingAs($this->staff('admin'));

        $this->get('/patients')->assertOk()
            ->assertSee('Archived Patients')
            ->assertSee('Add Patient')
            ->assertDontSee('Back to current patients');

        $this->get('/patients?archived=1')->assertOk()
            ->assertSee('Back to current patients')
            ->assertSee('Add Patient');
    }

    public function test_list_is_scoped_by_role(): void
    {
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))->get('/patients')
            ->assertOk()->assertSee('Olive One')->assertDontSee('Tom Two')->assertDontSee('Otto Archived');

        $this->actingAs($this->staff('admin'))->get('/patients')
            ->assertOk()->assertSee('Olive One')->assertSee('Tom Two')->assertDontSee('Otto Archived');

        $this->actingAs($this->staff('staff'))->get('/patients?archived=1')
            ->assertOk()->assertSee('Otto Archived')->assertDontSee('Olive One');
    }

    public function test_search_and_condition_filter(): void
    {
        $this->actingAs($this->staff('admin'))->get('/patients?search=tom')
            ->assertSee('Tom Two')->assertDontSee('Olive One');
        $this->actingAs($this->staff('admin'))->get('/patients?condition=ACL')
            ->assertSee('Olive One')->assertDontSee('Tom Two');
    }

    public function test_therapist_creates_patient_with_app_login_assigned_to_them(): void
    {
        $response = $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))
            ->post('/patients', $this->newPatient());

        // Firebase Auth login with the temporary password; its uid keys everything else.
        $uid = $this->authUsers['nina@rehabplus.com']['uid'];
        $this->assertSame(['uid' => $uid, 'password' => 'temp-pass-1', 'disabled' => false, 'displayName' => 'Nina New'], $this->authUsers['nina@rehabplus.com']);
        $response->assertRedirect("/patients/{$uid}")->assertSessionHas('success');

        // users/{uid} + patients/{uid} created together, never overwriting.
        [$user, $patient] = $this->commits[0];
        $this->assertSame(self::ROOT."/users/{$uid}", $user['update']['name']);
        $this->assertSame(['exists' => false], $patient['currentDocument']);
        $this->assertSame(['role' => 'patient', 'name' => 'Nina New', 'email' => 'nina@rehabplus.com', 'active' => true], array_diff_key($this->docs["users/{$uid}"], ['createdAt' => 1]));

        $doc = $this->docs["patients/{$uid}"];
        $this->assertSame('thA', $doc['therapistId']);
        $this->assertSame('Dr. Ana', $doc['therapistName']);
        $this->assertSame('Ankle sprain', $doc['condition']);
        $this->assertSame('Inversion sprain', $doc['medicalSummary']);
        $this->assertSame('Balance work', $doc['therapyPlan']);
        $this->assertSame('+639175550101', $doc['phone']);
        $this->assertSame('1990-05-14', $doc['dob']);
        $this->assertSame('nina@rehabplus.com', $doc['email']);
        $this->assertFalse($doc['archived']);
        $this->assertInstanceOf(CarbonImmutable::class, $doc['createdAt']);
    }

    public function test_patient_login_must_use_the_clinic_domain(): void
    {
        $this->actingAs($this->staff('admin'))->from('/patients/create')
            ->post('/patients', $this->newPatient(['email' => 'nina@yahoo.com']))
            ->assertRedirect('/patients/create')
            ->assertSessionHasErrors(['email' => OfficialEmailDomain::MESSAGE]);

        $this->get('/patients/create')->assertOk()->assertSee('invalid-feedback', false)->assertSee(OfficialEmailDomain::MESSAGE);
        $this->assertArrayNotHasKey('nina@yahoo.com', $this->authUsers);
        $this->assertSame([], $this->commits);
    }

    public function test_phone_number_must_have_the_digits_of_the_chosen_country(): void
    {
        $user = $this->staff('admin');

        $this->actingAs($user)->from('/patients/create')
            ->post('/patients', $this->newPatient(['phone' => '917555010']))
            ->assertSessionHasErrors(['phone' => 'Enter exactly 10 digits for the phone number in Philippines.']);

        $this->actingAs($user)->from('/patients/create')
            ->post('/patients', $this->newPatient(['phone' => '0917abc']))
            ->assertSessionHasErrors(['phone' => 'Phone number can only contain numbers.']);

        // The same length check follows the country picked, not a fixed one.
        $this->actingAs($user)->from('/patients/create')
            ->post('/patients', $this->newPatient(['phone_country' => 'AU', 'phone' => '412345678']))
            ->assertSessionHasNoErrors();
        $uid = $this->authUsers['nina@rehabplus.com']['uid'];
        $this->assertSame('+61412345678', $this->docs["patients/{$uid}"]['phone']);
    }

    public function test_editing_shows_the_saved_country_and_number(): void
    {
        $this->docs['patients/pOne']['phone'] = '+12025550123';

        $this->actingAs($this->staff('admin'))->get('/patients/pOne/edit')
            ->assertOk()
            ->assertSee('<option value="US" data-dial="1" data-min="10" data-max="10" data-digits="10 digits" data-example="2025550123" selected>', false)
            ->assertSee('value="2025550123"', false);
    }

    public function test_birth_date_is_checked(): void
    {
        $user = $this->staff('admin');

        $this->actingAs($user)->from('/patients/create')
            ->post('/patients', $this->newPatient(['dob' => 'January 14, 2000']))
            ->assertSessionHasErrors(['dob' => 'Pick the date of birth from the calendar.']);

        $this->actingAs($user)->from('/patients/create')
            ->post('/patients', $this->newPatient(['dob' => now()->addDay()->toDateString()]))
            ->assertSessionHasErrors(['dob' => "Date of birth can't be in the future."]);

        $this->assertArrayNotHasKey('nina@rehabplus.com', $this->authUsers);
        $this->assertSame([], $this->commits);
    }

    public function test_admin_picks_the_therapist(): void
    {
        $this->actingAs($this->staff('admin'))
            ->post('/patients', $this->newPatient(['therapist_id' => 'thB']))
            ->assertRedirect();

        $doc = collect($this->docs)->first(fn ($d, $p) => str_starts_with($p, 'patients/newUid') && substr_count($p, '/') === 1);
        $this->assertSame('thB', $doc['therapistId']);
        $this->assertSame('Dr. Ben', $doc['therapistName']);
    }

    public function test_front_desk_staff_cannot_add_patients(): void
    {
        $this->actingAs($this->staff('staff'))->get('/patients/create')->assertForbidden();

        $this->actingAs($this->staff('admin'))->get('/patients/create')
            ->assertSee('placeholder="Patient"', false)
            ->assertSee('placeholder="patient@rehabplus.com"', false)
            ->assertSee('placeholder="**********"', false);
        $this->actingAs($this->staff('staff'))->post('/patients', $this->newPatient())->assertForbidden();
    }

    public function test_validation_and_taken_email(): void
    {
        $user = $this->staff('admin');
        $this->actingAs($user)->post('/patients', $this->newPatient(['password_confirmation' => 'different']))
            ->assertSessionHasErrors('password');
        $this->actingAs($user)->post('/patients', $this->newPatient(['password' => 'short', 'password_confirmation' => 'short']))
            ->assertSessionHasErrors('password');

        $this->authUsers['nina@rehabplus.com'] = ['uid' => 'existing', 'password' => 'x', 'disabled' => false, 'displayName' => 'x'];
        $this->actingAs($user)->from('/patients/create')->post('/patients', $this->newPatient())
            ->assertRedirect('/patients/create')
            ->assertSessionHas('error', 'That email address already has an account.')
            ->assertSessionHasInput('name', 'Nina New')
            ->assertSessionMissing('_old_input.password');
        $this->assertSame([], $this->commits);
    }

    public function test_login_is_deleted_again_if_firestore_write_fails(): void
    {
        $this->failCommits = true;

        $this->actingAs($this->staff('admin'))->from('/patients/create')->post('/patients', $this->newPatient())
            ->assertRedirect('/patients/create')
            ->assertSessionHas('error');

        $this->assertArrayNotHasKey('nina@rehabplus.com', $this->authUsers);
        $this->assertStringEndsWith('accounts:delete', end($this->authCalls)['url']);
    }

    public function test_therapist_cannot_see_or_change_another_therapists_patient(): void
    {
        $user = $this->staff('therapist', 'thA', 'Dr. Ana');
        $this->actingAs($user)->get('/patients/pTwo')->assertNotFound();
        $this->actingAs($user)->get('/patients/pTwo/edit')->assertNotFound();
        $this->actingAs($user)->put('/patients/pTwo', ['name' => 'X', 'condition' => 'Y'])->assertNotFound();
        $this->actingAs($user)->post('/patients/pTwo/archive')->assertNotFound();
        $this->assertSame([], $this->commits);
    }

    public function test_front_desk_sees_profile_but_not_clinical_records_or_edit(): void
    {
        $user = $this->staff('staff');
        $this->actingAs($user)->get('/patients/pOne')
            ->assertOk()->assertSee('Olive One')->assertDontSee('Assigned exercises')->assertDontSee('Therapy notes');
        $this->actingAs($user)->get('/patients/pOne/edit')->assertForbidden();
    }

    public function test_update_profile_and_admin_reassignment(): void
    {
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))
            ->put('/patients/pOne', ['name' => 'Olive Renamed', 'condition' => 'ACL reconstruction', 'phone' => '9175550101', 'therapist_id' => 'thB'])
            ->assertRedirect('/patients/pOne');

        $doc = $this->docs['patients/pOne'];
        $this->assertSame('Olive Renamed', $doc['name']);
        $this->assertSame('ACL reconstruction', $doc['condition']);
        $this->assertSame('thA', $doc['therapistId'], 'only admins reassign');
        $this->assertSame('Olive Renamed', $this->docs['users/pOne']['name']);
        $this->assertSame('Olive Renamed', $this->authUsers['pOne@mail.com']['displayName'] ?? 'Olive Renamed');

        $this->actingAs($this->staff('admin'))
            ->put('/patients/pOne', ['name' => 'Olive Renamed', 'condition' => 'ACL', 'therapist_id' => 'thB']);
        $this->assertSame('thB', $this->docs['patients/pOne']['therapistId']);
        $this->assertSame('Dr. Ben', $this->docs['patients/pOne']['therapistName']);
    }

    public function test_archive_disables_login_and_restore_reenables(): void
    {
        $this->authUsers['pOne@mail.com'] = ['uid' => 'pOne', 'password' => 'x', 'disabled' => false, 'displayName' => 'Olive One'];
        $user = $this->staff('therapist', 'thA', 'Dr. Ana');

        $this->actingAs($user)->post('/patients/pOne/archive')->assertRedirect('/patients');
        $this->assertTrue($this->authUsers['pOne@mail.com']['disabled']);
        $this->assertTrue($this->docs['patients/pOne']['archived']);
        $this->assertFalse($this->docs['users/pOne']['active']);

        $this->actingAs($user)->post('/patients/pOne/restore')->assertRedirect('/patients/pOne');
        $this->assertFalse($this->authUsers['pOne@mail.com']['disabled']);
        $this->assertFalse($this->docs['patients/pOne']['archived']);
    }

    public function test_temporary_password_reset(): void
    {
        $this->authUsers['pOne@mail.com'] = ['uid' => 'pOne', 'password' => 'old', 'disabled' => false, 'displayName' => 'Olive One'];

        $this->actingAs($this->staff('admin'))
            ->post('/patients/pOne/password', ['password' => 'new-temp-9', 'password_confirmation' => 'new-temp-9'])
            ->assertRedirect('/patients/pOne');

        $this->assertSame('new-temp-9', $this->authUsers['pOne@mail.com']['password']);
    }

    public function test_profile_shows_progress_from_app_sessions(): void
    {
        $now = CarbonImmutable::now();
        $this->docs['patients/pOne/prescriptions/rx1'] = ['exerciseType' => 'kneeExtension', 'targetReps' => 10, 'frequencyPerWeek' => 2, 'active' => true, 'createdAt' => $now->subDays(20)];
        $this->docs['patients/pOne/prescriptions/rx2'] = ['exerciseType' => 'wallSit', 'targetReps' => 3, 'holdSeconds' => 20, 'frequencyPerWeek' => 3, 'active' => false, 'createdAt' => $now->subDays(30)];
        $this->docs['patients/pOne/sessions/s1'] = ['exerciseId' => 'kneeExtension', 'exerciseName' => 'Knee Extension', 'prescriptionId' => 'rx1', 'startTime' => $now->subDays(1), 'completedReps' => 10, 'targetReps' => 10, 'rejectedReps' => 2, 'overallCompliance' => 0.8, 'painLevel' => 4, 'painNote' => 'Sore after', 'endedEarly' => false, 'outsideSchedule' => false];
        $this->docs['patients/pOne/sessions/s2'] = ['exerciseId' => 'kneeExtension', 'prescriptionId' => 'rx1', 'startTime' => $now->subDays(2), 'completedReps' => 4, 'targetReps' => 10, 'overallCompliance' => 0.6, 'painLevel' => 6, 'endedEarly' => true, 'outsideSchedule' => true];
        $this->docs['patients/pOne/goals/g1'] = ['title' => 'Walk 1km', 'status' => 'achieved', 'progress' => 100, 'createdAt' => $now];
        $this->docs['patients/pOne/goals/g2'] = ['title' => 'Climb stairs', 'status' => 'active', 'progress' => 40, 'createdAt' => $now];

        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))->get('/patients/pOne')
            ->assertOk()
            ->assertSee('Knee Extension')
            ->assertSee('Wall Sit')
            ->assertSee('Stopped')
            ->assertSee('1/2 sessions')      // only the completed session counts this week
            ->assertSee('50%')               // adherence
            ->assertSee('70%')               // accuracy (0.8 + 0.6) / 2
            ->assertSee('5/10')              // average pain
            ->assertSee('Ended early')
            ->assertSee('Outside schedule')
            ->assertSee('Sore after')
            ->assertSee('Climb stairs')
            ->assertSee('50% achieved');
    }

    public function test_sessions_with_wrong_field_types_do_not_break_the_profile(): void
    {
        // Sessions come from the patient's phone; a patient talking to Firestore
        // directly could store any type here (this used to make the page 500).
        $now = CarbonImmutable::now();
        $this->docs['patients/pOne/sessions/bad'] = [
            'exerciseId' => 'kneeExtension', 'exerciseName' => ['evil' => 'map'], 'prescriptionId' => ['x'],
            'startTime' => $now->subHour(), 'completedReps' => 2000000000, 'targetReps' => 'ten',
            'rejectedReps' => ['x' => 1], 'overallCompliance' => 5, 'painLevel' => 99,
            'painNote' => ['not' => 'text'], 'endedEarly' => 'yes', 'outsideSchedule' => 1,
        ];

        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))->get('/patients/pOne')
            ->assertOk()
            ->assertSee('Knee Extension')                     // name falls back to the catalog
            ->assertSee(PatientProgress::MAX_COUNT.'/0')      // reps clamped, bad target -> 0
            ->assertSee('100%')                               // accuracy clamped to 0..1
            ->assertSee('10/10')                              // pain clamped to 0..10
            ->assertDontSee('Ended early')
            ->assertDontSee('Outside schedule');
    }

    public function test_session_text_and_numbers_are_kept_when_valid(): void
    {
        $s = PatientProgress::presentSession([
            '_id' => 's', '_path' => 'patients/pOne/sessions/s', 'exerciseId' => 'wallSit', 'exerciseName' => 'Wall Sit',
            'startTime' => CarbonImmutable::now(), 'completedReps' => 3, 'targetReps' => 5, 'overallCompliance' => 0.75,
            'painLevel' => 2, 'painNote' => str_repeat('a', 400), 'endedEarly' => true,
        ]);

        $this->assertSame('Wall Sit', $s['exerciseName']);
        $this->assertSame([3, 5, 75.0, 2, true], [$s['completedReps'], $s['targetReps'], $s['accuracy'], $s['painLevel'], $s['endedEarly']]);
        $this->assertSame(300, mb_strlen($s['painNote']));
        $this->assertNull(PatientProgress::presentSession(['_id' => 's', '_path' => 'p/x/sessions/s', 'startTime' => 'yesterday'])['startTime']);
    }

    public function test_changing_a_patient_asks_do_you_want_to_proceed_first(): void
    {
        $therapist = $this->staff('therapist', 'thA', 'Dr. Ana');

        // Edit form: lists the changed fields against the saved values.
        $this->actingAs($therapist)->get('/patients/pOne/edit')->assertOk()
            ->assertSee("data-confirm-changes=\"Save these changes to Olive One's profile?\"", false)
            ->assertSee('data-initial="Olive One"', false)
            ->assertSee('data-initial="ACL"', false);

        // Archive (red Proceed) and new password on the profile page.
        $this->actingAs($therapist)->get('/patients/pOne')->assertOk()
            ->assertSee('data-confirm="Archive Olive One?', false)
            ->assertSee('data-confirm-danger', false)
            ->assertSee('data-confirm="Set a new app password for Olive One?', false);

        // Restore on an archived patient.
        $this->actingAs($therapist)->get('/patients/pOld')->assertOk()
            ->assertSee('data-confirm="Restore Otto Archived?', false);

        // Creating a patient isn't a change to confirm.
        $this->actingAs($therapist)->get('/patients/create')->assertOk()
            ->assertDontSee('data-confirm', false);
    }
}
