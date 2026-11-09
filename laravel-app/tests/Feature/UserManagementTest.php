<?php

namespace Tests\Feature;

use App\Rules\OfficialEmailDomain;
use App\Services\User\EmailAvailability;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** Staff accounts: Firebase Auth logins + users/{uid} roles, admin only. */
class UserManagementTest extends TestCase
{
    use FakeFirebase;

    public function test_only_admins_manage_staff(): void
    {
        $this->actingAs($this->staff('therapist'))->get('/users')->assertForbidden();
        $this->actingAs($this->staff('therapist'))->post('/users', [])->assertForbidden();
    }

    public function test_list_shows_staff_but_not_patients(): void
    {
        $this->staff('therapist', 'th1', 'Dr. Lee');
        $this->patientDoc('pat1', ['name' => 'Patty Patient']);

        $this->actingAs($this->staff('admin', 'adm', 'Ada Admin'))->get('/users')->assertOk()
            ->assertSee('Dr. Lee')->assertSee('Ada Admin')->assertDontSee('Patty Patient')
            ->assertSee('Patient app accounts');
    }

    public function test_create_staff_account(): void
    {
        $this->actingAs($this->staff('admin'))->post('/users', [
            'name' => 'Dr. New', 'email' => 'New@RehabPlus.com', 'password' => 'long-enough', 'role' => 'therapist',
            'phone_country' => 'PH', 'phone' => '9171234567', 'contact_email' => 'Dr.New@Gmail.com',
        ])->assertRedirect('/users');

        $uid = $this->authUsers['new@rehabplus.com']['uid'];
        $this->assertSame('long-enough', $this->authUsers['new@rehabplus.com']['password']);
        $this->assertSame([
            'role' => 'therapist', 'name' => 'Dr. New', 'email' => 'new@rehabplus.com',
            'contactPhone' => '+639171234567', 'contactEmail' => 'dr.new@gmail.com', 'active' => true,
        ], array_diff_key($this->docs["users/{$uid}"], ['createdAt' => 1]));
    }

    public function test_personal_contact_details_are_optional_when_creating_an_account(): void
    {
        $this->actingAs($this->staff('admin'))->post('/users', [
            'name' => 'Dr. New', 'email' => 'new@rehabplus.com', 'password' => 'long-enough', 'role' => 'therapist',
        ])->assertRedirect('/users')->assertSessionHasNoErrors();

        $uid = $this->authUsers['new@rehabplus.com']['uid'];
        $this->assertSame(['', ''], [$this->docs["users/{$uid}"]['contactPhone'], $this->docs["users/{$uid}"]['contactEmail']]);
    }

    public function test_personal_contact_email_cannot_be_the_clinic_login_address(): void
    {
        $this->actingAs($this->staff('admin'))->from('/users/create')->post('/users', [
            'name' => 'Dr. New', 'email' => 'new@rehabplus.com', 'password' => 'long-enough', 'role' => 'therapist',
            'phone_country' => 'PH', 'phone' => '9171234567', 'contact_email' => 'new@rehabplus.com',
        ])->assertSessionHasErrors(['contact_email']);

        $this->assertArrayNotHasKey('new@rehabplus.com', $this->authUsers);
    }

    public function test_contact_details_can_be_changed_and_cleared_when_editing_an_account(): void
    {
        $this->staff('therapist', 'th1', 'Dr. Lee');
        $this->docs['users/th1']['contactPhone'] = '+639171234567';
        $this->docs['users/th1']['contactEmail'] = 'lee@gmail.com';

        $this->actingAs($this->staff('admin'))->put('/users/th1', [
            'name' => 'Dr. Lee', 'phone_country' => 'US', 'phone' => '2025550123', 'contact_email' => 'lee.clinic@gmail.com',
        ])->assertRedirect('/users');
        $this->assertSame(['+12025550123', 'lee.clinic@gmail.com'], [$this->docs['users/th1']['contactPhone'], $this->docs['users/th1']['contactEmail']]);

        $this->actingAs($this->staff('admin'))->put('/users/th1', ['name' => 'Dr. Lee'])->assertRedirect('/users');
        $this->assertSame(['', ''], [$this->docs['users/th1']['contactPhone'], $this->docs['users/th1']['contactEmail']]);
    }

    public function test_a_staff_account_cannot_use_an_email_a_patient_already_has(): void
    {
        $this->patientDoc('pmaria');

        $this->actingAs($this->staff('admin'))->from('/users/create')->post('/users', [
            'name' => 'Dr. Copy', 'email' => 'pmaria@mail.com', 'password' => 'long-enough', 'role' => 'therapist',
            'phone_country' => 'PH', 'phone' => '9171234567', 'contact_email' => 'copy@gmail.com',
        ])->assertSessionHasErrors(['email' => EmailAvailability::TAKEN_MESSAGE]);

        $this->assertSame([], $this->commits);
    }

    public function test_staff_account_must_use_the_clinic_domain(): void
    {
        $this->actingAs($this->staff('admin'))->from('/users/create')->post('/users', [
            'name' => 'Gmail User', 'email' => 'someone@gmail.com', 'password' => 'long-enough', 'role' => 'therapist',
        ])->assertRedirect('/users/create')->assertSessionHasErrors(['email' => OfficialEmailDomain::MESSAGE]);

        $this->get('/users/create')->assertOk()->assertSee('invalid-feedback', false)->assertSee(OfficialEmailDomain::MESSAGE);
        $this->assertArrayNotHasKey('someone@gmail.com', $this->authUsers);
        $this->assertSame([], $this->commits);
    }

    public function test_new_account_form_shows_the_role_name_and_email_as_placeholders(): void
    {
        $this->actingAs($this->staff('admin'))->get('/users/create')
            ->assertOk()
            ->assertSee('placeholder="Physical Therapist"', false)
            ->assertSee('placeholder="therapist@rehabplus.com"', false)
            ->assertSee('data-email="admin@rehabplus.com"', false)
            ->assertSee('placeholder="**********"', false);
    }

    public function test_patient_role_cannot_be_given_here(): void
    {
        $this->actingAs($this->staff('admin'))->post('/users', [
            'name' => 'X', 'email' => 'x@rehabplus.com', 'password' => 'long-enough', 'role' => 'patient',
        ])->assertSessionHasErrors('role');
        $this->assertArrayNotHasKey('x@rehabplus.com', $this->authUsers);
    }

    public function test_role_defaults_to_physical_therapist(): void
    {
        $this->actingAs($this->staff('admin'))->post('/users', [
            'name' => 'Fran', 'email' => 'fran@rehabplus.com', 'password' => 'long-enough',
            'phone' => '9171234567', 'contact_email' => 'fran@gmail.com',
        ]);

        $this->assertSame('therapist', $this->docs['users/'.$this->authUsers['fran@rehabplus.com']['uid']]['role']);
    }

    public function test_admin_can_change_a_therapist_to_administrator_and_the_rename_reaches_their_patients(): void
    {
        $this->staff('therapist', 'th1', 'Dr. Lee');
        $this->patientDoc('pat1', ['therapistId' => 'th1', 'therapistName' => 'Dr. Lee']);
        $this->patientDoc('pat2', ['therapistId' => 'other', 'therapistName' => 'Dr. Other']);

        $this->actingAs($this->staff('admin'))->put('/users/th1', ['name' => 'Dr. Lee-Santos', 'role' => 'admin', 'password' => 'brand-new-pw'])
            ->assertRedirect('/users');

        $this->assertSame('admin', $this->docs['users/th1']['role']);
        $this->assertSame('Dr. Lee-Santos', $this->docs['users/th1']['name']);
        $this->assertSame('Dr. Lee-Santos', $this->docs['patients/pat1']['therapistName']);
        $this->assertSame('Dr. Other', $this->docs['patients/pat2']['therapistName']);
        $this->assertSame('brand-new-pw', $this->authUsers['th1@rehabplus.com']['password']);
    }

    public function test_the_role_list_leaves_out_the_current_role(): void
    {
        $this->staff('therapist', 'th1', 'Dr. Lee');

        $this->actingAs($this->staff('admin'))->get('/users/th1/edit')->assertOk()
            ->assertSee('Current: Physical Therapist')
            ->assertDontSee('<option value="therapist"', false)
            ->assertSee('<option value="admin"', false);
    }

    public function test_the_last_active_administrator_cannot_be_changed_to_therapist(): void
    {
        $admin = $this->staff('admin', 'adm', 'Ada Admin');

        $this->actingAs($admin)->from('/users/adm/edit')->put('/users/adm', ['name' => 'Ada Admin', 'role' => 'therapist'])
            ->assertRedirect('/users/adm/edit')
            ->assertSessionHas('error');

        $this->assertSame('admin', $this->docs['users/adm']['role']);
    }

    public function test_an_administrator_can_be_changed_to_therapist_when_another_administrator_remains(): void
    {
        $this->staff('admin', 'adm2', 'Second Admin');

        $this->actingAs($this->staff('admin', 'adm', 'Ada Admin'))->put('/users/adm2', ['name' => 'Second Admin', 'role' => 'therapist'])
            ->assertRedirect('/users');

        $this->assertSame('therapist', $this->docs['users/adm2']['role']);
    }

    public function test_admin_cannot_change_own_role_or_disable_self(): void
    {
        $admin = $this->staff('admin', 'adm');

        $this->actingAs($admin)->put('/users/adm', ['name' => 'Still Admin', 'role' => 'therapist']);
        $this->assertSame('admin', $this->docs['users/adm']['role']);

        $this->actingAs($admin)->from('/users')->post('/users/adm/status', ['active' => 0])->assertSessionHas('error');
        $this->assertFalse($this->authUsers['adm@rehabplus.com']['disabled']);
    }

    public function test_disable_and_enable_account(): void
    {
        $this->staff('therapist', 'st1', 'Sam');

        $this->actingAs($this->staff('admin'))->from('/users')->post('/users/st1/status', ['active' => 0])->assertRedirect('/users');
        $this->assertTrue($this->authUsers['st1@rehabplus.com']['disabled']);
        $this->assertFalse($this->docs['users/st1']['active']);

        $this->actingAs($this->staff('admin'))->post('/users/st1/status', ['active' => 1]);
        $this->assertFalse($this->authUsers['st1@rehabplus.com']['disabled']);
        $this->assertTrue($this->docs['users/st1']['active']);
    }

    public function test_delete_removes_login_and_staff_record_only_after_archiving(): void
    {
        $this->staff('therapist', 'st1', 'Sam');
        $admin = $this->staff('admin');

        $this->actingAs($admin)->from('/users')->delete('/users/st1')->assertSessionHas('error');
        $this->assertArrayHasKey('users/st1', $this->docs);

        $this->actingAs($admin)->from('/users')->post('/users/st1/archive')->assertRedirect('/users');
        $this->actingAs($admin)->from('/users')->delete('/users/st1')
            ->assertRedirect('/users?archived=1')->assertSessionHas('success');

        $this->assertArrayNotHasKey('st1@rehabplus.com', $this->authUsers);
        $this->assertArrayNotHasKey('users/st1', $this->docs);
        $this->assertContains('users/st1', $this->deleted);
    }

    public function test_archive_takes_the_account_off_the_list_and_restore_brings_it_back(): void
    {
        $this->staff('therapist', 'st1', 'Sam Therapist');
        $admin = $this->staff('admin', 'adm1', 'Ada Admin');

        $this->actingAs($admin)->from('/users')->post('/users/st1/archive')->assertSessionHas('success');
        $this->assertTrue($this->authUsers['st1@rehabplus.com']['disabled']);
        $this->assertTrue($this->docs['users/st1']['archived']);
        $this->assertFalse($this->docs['users/st1']['active']);

        $this->actingAs($admin)->get('/users')->assertOk()->assertDontSee('Sam Therapist');
        $this->actingAs($admin)->get('/users?archived=1')->assertOk()
            ->assertSee('Sam Therapist')
            ->assertSee('by Ada Admin')
            ->assertSee('Delete permanently');

        $this->actingAs($admin)->from('/users?archived=1')->post('/users/st1/restore')
            ->assertRedirect('/users')->assertSessionHas('success');
        $this->assertFalse($this->authUsers['st1@rehabplus.com']['disabled']);
        $this->assertFalse($this->docs['users/st1']['archived']);
        $this->assertTrue($this->docs['users/st1']['active']);
        $this->actingAs($admin)->get('/users')->assertOk()->assertSee('Sam Therapist');
    }

    public function test_an_archived_therapist_with_patients_still_has_to_be_reassigned_before_deleting(): void
    {
        $admin = $this->staff('admin');
        $this->staff('therapist', 'th1', 'Dr. Lee');
        $this->patientDoc('pat1', ['therapistId' => 'th1', 'therapistName' => 'Dr. Lee']);

        $this->actingAs($admin)->post('/users/th1/archive');
        $this->actingAs($admin)->from('/users?archived=1')->delete('/users/th1')->assertSessionHas('error');

        $this->assertArrayHasKey('users/th1', $this->docs);
    }

    public function test_an_admin_cannot_archive_themselves(): void
    {
        $admin = $this->staff('admin', 'adm');

        $this->actingAs($admin)->from('/users')->post('/users/adm/archive')->assertSessionHas('error');

        $this->assertFalse($this->docs['users/adm']['archived'] ?? false);
    }

    public function test_leftover_record_without_login_is_flagged_and_deletable(): void
    {
        $this->staff('admin', 'gone', 'Old Admin', 'you@rehabplus.com');
        unset($this->authUsers['you@rehabplus.com']); // login deleted in the Firebase console
        $admin = $this->staff('admin', 'adm', 'Ada Admin');

        $this->actingAs($admin)->get('/users')->assertOk()->assertSee('Old Admin')->assertSee('No login');

        $this->actingAs($admin)->from('/users')->delete('/users/gone')->assertRedirect('/users')->assertSessionHas('success');
        $this->assertArrayNotHasKey('users/gone', $this->docs);
        $this->actingAs($admin)->get('/users')->assertDontSee('Old Admin')->assertDontSee('No login');
    }

    public function test_cannot_delete_self_or_therapist_with_patients(): void
    {
        $admin = $this->staff('admin', 'adm');
        $this->staff('therapist', 'th1', 'Dr. Lee');
        $this->patientDoc('pat1', ['therapistId' => 'th1', 'therapistName' => 'Dr. Lee']);

        $this->actingAs($admin)->from('/users')->delete('/users/adm')->assertSessionHas('error');
        $this->actingAs($admin)->from('/users')->delete('/users/th1')->assertSessionHas('error');

        $this->assertArrayHasKey('users/adm', $this->docs);
        $this->assertArrayHasKey('users/th1', $this->docs);
        $this->assertArrayHasKey('th1@rehabplus.com', $this->authUsers);
    }

    public function test_only_admins_can_delete_and_patients_cannot_be_deleted_here(): void
    {
        $this->staff('therapist', 'st1');
        $this->patientDoc('pat1');

        $this->actingAs($this->staff('therapist'))->delete('/users/st1')->assertForbidden();
        $this->actingAs($this->staff('admin'))->delete('/users/pat1')->assertNotFound();
        $this->assertArrayHasKey('users/st1', $this->docs);
        $this->assertArrayHasKey('users/pat1', $this->docs);
    }

    public function test_patients_are_not_editable_here(): void
    {
        $this->patientDoc('pat1');

        $this->actingAs($this->staff('admin'))->get('/users/pat1/edit')->assertNotFound();
    }

    public function test_make_admin_command_creates_the_first_admin(): void
    {
        $this->artisan('rehab:make-admin', ['email' => 'Boss@RehabPlus.com', 'name' => 'Clinic Boss'])
            ->expectsQuestion('Password for the new admin (min 8 characters)', 'boss-password')
            ->expectsQuestion('Repeat the password', 'boss-password')
            ->assertSuccessful();

        $uid = $this->authUsers['boss@rehabplus.com']['uid'];
        $this->assertSame('admin', $this->docs["users/{$uid}"]['role']);

        // Running it for an existing staff login promotes it without touching the password.
        $this->staff('therapist', 'st1', 'Sam', 'sam@rehabplus.com');
        $this->artisan('rehab:make-admin', ['email' => 'sam@rehabplus.com', 'name' => 'Sam'])->assertSuccessful();
        $this->assertSame('admin', $this->docs['users/st1']['role']);
        $this->assertSame('secret-pass', $this->authUsers['sam@rehabplus.com']['password']);
    }

    public function test_make_admin_command_rejects_other_domains(): void
    {
        $this->artisan('rehab:make-admin', ['email' => 'boss@yahoo.com', 'name' => 'Boss'])
            ->assertFailed();

        $this->assertArrayNotHasKey('boss@yahoo.com', $this->authUsers);
        $this->assertSame([], $this->commits);
    }
}
