<?php

namespace Tests\Feature;

use App\Rules\OfficialEmailDomain;
use App\Services\Patient\PatientProgress;
use App\Services\User\EmailAvailability;
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
            'password' => 'tempPass1', 'password_confirmation' => 'tempPass1',
            'phone_country' => 'PH', 'phone' => '9175550101', 'dob' => '1990-05-14',
            'medical_summary' => 'Inversion sprain', 'therapy_plan' => 'Balance work',
        ];
    }

    public function test_list_has_an_archive_button_with_confirmation_for_patients_you_manage(): void
    {
        $this->actingAs($this->staff('admin'))->get('/patients')
            ->assertOk()
            ->assertSee('action="http://localhost/patients/pOne/archive"', false)
            ->assertSee('action="http://localhost/patients/pTwo/archive"', false)
            ->assertDontSee('action="http://localhost/patients/pOld/archive"', false)
            ->assertSee('data-confirm="Archive Olive One?', false);

        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))->get('/patients')
            ->assertOk()
            ->assertSee('action="http://localhost/patients/pOne/archive"', false)
            ->assertDontSee('action="http://localhost/patients/pTwo/archive"', false);

        $this->actingAs($this->staff('admin'))->get('/patients?archived=1')
            ->assertOk()
            ->assertDontSee('/patients/pOld/archive', false);
    }

    public function test_permanent_delete_removes_the_record_everything_under_it_and_the_login(): void
    {
        $this->patientDoc('pGone', ['name' => 'Gina Gone', 'therapistId' => 'thB', 'archived' => true]);
        $this->docs['patients/pGone/sessions/s1'] = ['startTime' => CarbonImmutable::now()];
        $this->docs['patients/pGone/prescriptions/rx1'] = ['active' => true];
        $this->docs['patients/pGone/threads/t1'] = ['unreadForStaff' => 0];
        $this->docs['patients/pGone/threads/t1/messages/m1'] = ['text' => 'hello'];

        $this->actingAs($this->staff('admin'))->post('/patients/pGone/delete')
            ->assertRedirect('/patients')
            ->assertSessionHas('success');

        $this->assertSame([], array_values(array_filter(array_keys($this->docs), fn ($k) => str_starts_with($k, 'patients/pGone'))));
        $this->assertArrayNotHasKey('users/pGone', $this->docs);
        $this->assertArrayNotHasKey('pGone@mail.com', $this->authUsers);
        $this->assertArrayHasKey('patients/pOne', $this->docs);
    }

    public function test_admin_can_delete_an_active_patient_without_archiving_first(): void
    {
        $this->actingAs($this->staff('admin'))->post('/patients/pOne/delete')
            ->assertRedirect('/patients')
            ->assertSessionHas('success');

        $this->assertArrayNotHasKey('patients/pOne', $this->docs);
        $this->assertArrayNotHasKey('pOne@mail.com', $this->authUsers);
    }

    public function test_messages_are_deleted_before_the_patient_document(): void
    {
        $this->patientDoc('pGone', ['archived' => true]);
        $this->docs['patients/pGone/threads/t1'] = ['unreadForStaff' => 0];
        $this->docs['patients/pGone/threads/t1/messages/m1'] = ['text' => 'hello'];

        $this->actingAs($this->staff('admin'))->post('/patients/pGone/delete');

        $deletes = [];
        foreach ($this->commits as $commit) {
            foreach ($commit as $write) {
                if (isset($write['delete'])) {
                    $deletes[] = $write['delete'];
                }
            }
        }
        $messageAt = array_search(true, array_map(fn ($d) => str_ends_with($d, '/threads/t1/messages/m1'), $deletes), true);
        $patientAt = array_search(true, array_map(fn ($d) => str_ends_with($d, '/patients/pGone'), $deletes), true);

        $this->assertNotFalse($messageAt);
        $this->assertNotFalse($patientAt);
        $this->assertLessThan($patientAt, $messageAt);
    }

    public function test_patient_list_has_message_and_delete_buttons_for_the_right_staff(): void
    {
        $this->actingAs($this->staff('admin'))->get('/patients')
            ->assertOk()
            ->assertSee('href="http://localhost/messages/pOne"', false)
            ->assertSee("This will permanently delete the patient's account, including all their records and conversations.", false)
            ->assertSee('>Delete<', false);

        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))->get('/patients')
            ->assertOk()
            ->assertDontSee('href="http://localhost/messages/pTwo"', false)
            ->assertDontSee('>Delete<', false);
    }

    public function test_therapists_cannot_delete_permanently(): void
    {
        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))->post('/patients/pOld/delete')->assertForbidden();

        $this->assertArrayHasKey('patients/pOld', $this->docs);
    }

    public function test_restore_returns_to_the_page_the_button_was_on(): void
    {
        $this->actingAs($this->staff('admin'))
            ->withHeader('referer', 'http://localhost/patients?archived=1')
            ->post('/patients/pOld/restore')
            ->assertRedirect('http://localhost/patients?archived=1');
    }

    public function test_archived_list_offers_restore_and_delete_only_to_the_right_roles(): void
    {
        $this->actingAs($this->staff('admin'))->get('/patients?archived=1')
            ->assertOk()
            ->assertSee('/patients/pOld/restore', false)
            ->assertSee('/patients/pOld/delete', false);

        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))->get('/patients?archived=1')
            ->assertOk()
            ->assertSee('/patients/pOld/restore', false)
            ->assertDontSee('/patients/pOld/delete', false);
    }

    public function test_archived_list_shows_when_and_by_whom_a_patient_was_archived(): void
    {
        $this->actingAs($this->staff('admin', 'adm1', 'Dr. Admin'))->post('/patients/pTwo/archive')->assertRedirect('/patients');

        $this->assertSame('Dr. Admin', $this->docs['patients/pTwo']['archivedByName']);
        $this->assertInstanceOf(CarbonImmutable::class, $this->docs['patients/pTwo']['archivedAt']);

        $this->get('/patients?archived=1')->assertOk()
            ->assertSee('Archived')
            ->assertSee('by Dr. Admin')
            ->assertSee(now()->format('M j, Y'));

        $this->post('/patients/pTwo/restore')->assertRedirect();
        $this->assertNull($this->docs['patients/pTwo']['archivedAt']);
        $this->assertNull($this->docs['patients/pTwo']['archivedByName']);
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

        $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))->get('/patients?archived=1')
            ->assertOk()->assertSee('Otto Archived')->assertDontSee('Olive One');
    }

    public function test_search_and_condition_filter(): void
    {
        $this->actingAs($this->staff('admin'))->get('/patients?search=tom')
            ->assertSee('Tom Two')->assertDontSee('Olive One');
        $this->actingAs($this->staff('admin'))->get('/patients?condition=ACL')
            ->assertSee('Olive One')->assertDontSee('Tom Two');
        $this->actingAs($this->staff('admin'))->get('/patients')
            ->assertSee('data-autosubmit', false)
            ->assertSee('placeholder="Name or email"', false)
            ->assertSee('aria-label="Search patients"', false)
            ->assertDontSee('>Filter<', false)
            ->assertDontSee('>Clear<', false);
    }

    public function test_search_matches_name_or_email_not_condition(): void
    {
        $this->actingAs($this->staff('admin'))->get('/patients?search=ACL')
            ->assertDontSee('Olive One');
    }

    public function test_the_add_patient_form_starts_with_no_password_and_the_button_makes_one(): void
    {
        $admin = $this->staff('admin');
        $page = $this->actingAs($admin)->get('/patients/create')->assertOk()
            ->assertSee('data-generate-password="#password"', false)
            ->assertDontSee('password_confirmation', false)
            ->assertDontSee('Generate another', false)
            ->getContent();
        $this->assertMatchesRegularExpression('/id="password" type="text" name="password"[^>]*value=""/', $page, 'no password is shown before the button is used');
        $this->assertMatchesRegularExpression('/id="password"[^>]*readonly/', $page, 'the password box is locked until the button is used');

        $generated = $this->actingAs($admin)->getJson('/patients/temporary-password')->assertOk()->json('password');
        $this->assertMatchesRegularExpression('/^[A-Za-z]+\d{4}$/', $generated);

        $this->actingAs($admin)->post('/patients', $this->newPatient(['password' => $generated]))
            ->assertSessionHas('success', fn ($message) => str_contains($message, "Temporary password: {$generated}."));
    }

    public function test_address_is_saved_and_shown_on_the_patient_profile(): void
    {
        $admin = $this->staff('admin');
        $address = 'Blk 2 Lot 5, Brgy. Tondo, Manila, Metro Manila';

        $this->actingAs($admin)->post('/patients', $this->newPatient([
            'address_street' => 'Blk 2 Lot 5', 'address_barangay' => 'Brgy. Tondo', 'address_city' => 'Manila', 'address_province' => 'Metro Manila',
        ]))->assertRedirect();
        $uid = $this->authUsers['nina@rehabplus.com']['uid'];
        $this->assertSame($address, $this->docs["patients/{$uid}"]['address']);
        $this->assertSame('Brgy. Tondo', $this->docs["patients/{$uid}"]['addressBarangay']);

        $this->actingAs($admin)->get("/patients/{$uid}")->assertOk()->assertSee($address);
        $this->actingAs($admin)->put("/patients/{$uid}", [
            'name' => 'Nina New', 'condition' => 'Ankle sprain', 'address_street' => 'New Street 9',
        ])->assertRedirect();
        $this->assertSame('New Street 9', $this->docs["patients/{$uid}"]['address']);
        $this->assertSame('', $this->docs["patients/{$uid}"]['addressBarangay']);
    }

    public function test_therapist_creates_patient_with_app_login_assigned_to_them(): void
    {
        $response = $this->actingAs($this->staff('therapist', 'thA', 'Dr. Ana'))
            ->post('/patients', $this->newPatient());

        // Firebase Auth login with the temporary password; its uid keys everything else.
        $uid = $this->authUsers['nina@rehabplus.com']['uid'];
        $this->assertSame(['uid' => $uid, 'password' => 'tempPass1', 'disabled' => false, 'displayName' => 'Nina New'], $this->authUsers['nina@rehabplus.com']);
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

    public function test_therapists_and_administrators_can_open_the_add_patient_form(): void
    {
        $this->actingAs($this->staff('therapist'))->get('/patients/create')->assertOk();

        $this->actingAs($this->staff('admin'))->get('/patients/create')
            ->assertSee('placeholder="Patient"', false)
            ->assertSee('placeholder="patient@rehabplus.com"', false)
            ->assertSee('data-generate-password', false);
    }

    public function test_temporary_password_cannot_contain_spaces_or_hyphens(): void
    {
        $user = $this->staff('admin');
        $this->actingAs($user)->post('/patients', $this->newPatient(['password' => 'Maple River 42']))
            ->assertSessionHasErrors(['password' => 'The temporary password cannot contain spaces or hyphens.']);
        $this->actingAs($user)->post('/patients', $this->newPatient(['password' => 'Maple-River-42']))
            ->assertSessionHasErrors('password');
        $this->assertSame([], $this->commits);
    }

    public function test_validation_and_taken_email(): void
    {
        $user = $this->staff('admin');
        $this->actingAs($user)->post('/patients', $this->newPatient(['password' => 'short']))
            ->assertSessionHasErrors('password');

        $this->authUsers['nina@rehabplus.com'] = ['uid' => 'existing', 'password' => 'x', 'disabled' => false, 'displayName' => 'x'];
        $this->actingAs($user)->from('/patients/create')->post('/patients', $this->newPatient())
            ->assertRedirect('/patients/create')
            ->assertSessionHasErrors(['email' => EmailAvailability::TAKEN_MESSAGE])
            ->assertSessionHasInput('name', 'Nina New');
        $this->assertSame([], $this->commits);
    }

    public function test_an_email_used_by_a_staff_account_is_refused_for_a_patient(): void
    {
        $this->staff('therapist', 'thA', 'Dr. Ana', 'ana@rehabplus.com');

        $this->actingAs($this->staff('admin'))->from('/patients/create')
            ->post('/patients', $this->newPatient(['email' => 'ana@rehabplus.com']))
            ->assertSessionHasErrors(['email' => EmailAvailability::TAKEN_MESSAGE]);
        $this->assertSame([], $this->commits, 'nothing is written for a taken email');
    }

    public function test_the_live_email_check_says_whether_an_email_is_taken(): void
    {
        $admin = $this->staff('admin');
        $this->patientDoc('pmaria'); // stored lowercase, like every saved email

        $this->actingAs($admin)->getJson('/email-check?email=PMaria@Mail.com')
            ->assertOk()->assertJson(['available' => false, 'message' => EmailAvailability::TAKEN_MESSAGE]);
        $this->actingAs($admin)->getJson('/email-check?email=fresh@rehabplus.com')
            ->assertOk()->assertJson(['available' => true, 'message' => '']);
        $this->actingAs($admin)->getJson('/email-check?email=not-an-email')
            ->assertOk()->assertJson(['available' => null]);
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

    public function test_a_therapist_cannot_open_another_therapists_patient(): void
    {
        $user = $this->staff('therapist', 'thB', 'Dr. Ben');
        $this->actingAs($user)->get('/patients/pOne')->assertNotFound();
        $this->actingAs($user)->get('/patients/pOne/edit')->assertNotFound();
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

    public function test_changing_the_medical_summary_or_therapy_plan_notifies_the_patient(): void
    {
        $this->patientDoc('pOne', ['medicalSummary' => 'Old summary', 'therapyPlan' => 'Old plan']);
        $this->docs['patients/pOne/devices/tok1'] = ['token' => 'tok1'];

        $this->actingAs($this->staff('admin'))
            ->put('/patients/pOne', ['name' => 'Olive One', 'condition' => 'ACL', 'medical_summary' => 'New summary', 'therapy_plan' => 'Old plan'])
            ->assertRedirect('/patients/pOne');

        $entries = $this->notificationFields('pOne');
        $this->assertCount(1, $entries);
        $this->assertSame('care_plan', $entries[0]['type']['stringValue']);
        $this->assertSame('Your medical summary was updated.', $entries[0]['body']['stringValue']);
        $this->assertCount(1, $this->pushes);
        $this->assertSame(['type' => 'care_plan'], $this->pushes[0]['data']);
    }

    public function test_saving_without_changing_the_care_plan_sends_no_notification(): void
    {
        $this->patientDoc('pOne', ['medicalSummary' => 'Same', 'therapyPlan' => 'Same']);

        $this->actingAs($this->staff('admin'))
            ->put('/patients/pOne', ['name' => 'Olive One', 'condition' => 'Renamed', 'medical_summary' => 'Same', 'therapy_plan' => 'Same']);

        $this->assertSame([], $this->notificationFields('pOne'));
        $this->assertSame([], $this->pushes);
    }

    /** The fields of every Notifications-page entry written for a patient in this request. */
    private function notificationFields(string $uid): array
    {
        $found = [];
        foreach ($this->commits as $commit) {
            foreach ($commit as $write) {
                if (str_contains($write['update']['name'] ?? '', "/patients/{$uid}/notifications/")) {
                    $found[] = $write['update']['fields'];
                }
            }
        }

        return $found;
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
