<?php

namespace Tests\Feature;

use App\Services\Firebase\FirestoreBytes;
use App\Services\Patient\PatientAvatarService;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** The patient's profile picture, and the grey and white default when there is none. */
class PatientAvatarTest extends TestCase
{
    use FakeFirebase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->staff('admin');
        $this->staff('therapist', 'thA', 'Dr. Ana');
        $this->patientDoc('pOne', ['name' => 'Olive One', 'therapistId' => 'thA', 'therapistName' => 'Dr. Ana']);
    }

    public function test_a_male_patient_without_a_picture_gets_the_male_silhouette(): void
    {
        $this->docs['patients/pOne']['gender'] = 'Male';

        $this->actingAs($this->staff('admin'))->get('/patients/pOne')->assertOk()
            ->assertSee('/assets/images/avatars/male.svg', false);
    }

    public function test_a_female_patient_without_a_picture_gets_the_female_silhouette(): void
    {
        $this->docs['patients/pOne']['gender'] = 'Female';

        $this->actingAs($this->staff('admin'))->get('/patients/pOne')->assertOk()
            ->assertSee('/assets/images/avatars/female.svg', false);
    }

    public function test_other_or_unset_gender_gets_the_neutral_default(): void
    {
        $this->docs['patients/pOne']['gender'] = 'Prefer not to say';
        $this->actingAs($this->staff('admin'))->get('/patients/pOne')->assertOk()
            ->assertSee('/assets/images/avatars/default.svg', false);

        $this->docs['patients/pOne']['gender'] = '';
        $this->actingAs($this->staff('admin'))->get('/patients/pOne')->assertOk()
            ->assertSee('/assets/images/avatars/default.svg', false);
    }

    public function test_the_default_silhouettes_are_published_files(): void
    {
        foreach ([PatientAvatarService::DEFAULT, PatientAvatarService::MALE, PatientAvatarService::FEMALE] as $path) {
            $this->assertFileExists(public_path($path));
        }
    }

    public function test_the_app_picture_replaces_the_default_when_it_is_there(): void
    {
        $this->docs['patients/pOne']['gender'] = 'Female';
        $this->docs['patients/pOne/avatar/photo'] = ['image' => new FirestoreBytes('fake-jpeg-bytes')];

        $this->actingAs($this->staff('admin'))->get('/patients/pOne')->assertOk()
            ->assertSee('data:image/jpeg;base64,'.base64_encode('fake-jpeg-bytes'), false)
            ->assertDontSee('/assets/images/avatars/female.svg', false);
    }

    public function test_a_picture_over_the_app_limit_is_ignored(): void
    {
        $this->docs['patients/pOne']['gender'] = 'Male';
        $this->docs['patients/pOne/avatar/photo'] = ['image' => new FirestoreBytes(str_repeat('x', PatientAvatarService::MAX_BYTES + 1))];

        $this->actingAs($this->staff('admin'))->get('/patients/pOne')->assertOk()
            ->assertSee('/assets/images/avatars/male.svg', false);
    }

    public function test_the_profile_keeps_its_actions_in_the_new_layout(): void
    {
        $this->actingAs($this->staff('admin'))->get('/patients/pOne')->assertOk()
            ->assertSee('data-patient-profile', false)
            ->assertSee('data-patient-actions', false)
            ->assertSee('Edit')
            ->assertSee('Reset password')
            ->assertSee('Archive')
            ->assertSee('Terms and consent');
    }
}
