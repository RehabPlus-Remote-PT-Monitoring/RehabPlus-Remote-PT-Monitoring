<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CreateAccountRoleTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->actingAs(User::factory()->create(['role' => 'superadmin', 'is_active' => true]));
    }

    public function test_create_account_form_has_no_patient_role(): void
    {
        $this->get('/users/create')
            ->assertOk()
            ->assertSee('value="therapist"', false)
            ->assertDontSee('value="patient"', false);
    }

    public function test_patient_role_is_rejected_when_creating_an_account(): void
    {
        $this->post('/users', [
            'name' => 'Sneaky Patient',
            'email' => 'sneaky@rehabplus.com',
            'password' => 'secret123',
            'role' => 'patient',
        ])->assertSessionHasErrors('role');

        $this->assertDatabaseMissing('users', ['email' => 'sneaky@rehabplus.com']);
    }

    public function test_staff_account_can_still_be_created(): void
    {
        $this->post('/users', [
            'name' => 'Dr. New Therapist',
            'email' => 'therapist@rehabplus.com',
            'password' => 'secret123',
            'role' => 'therapist',
        ])->assertRedirect('/users');

        $this->assertDatabaseHas('users', ['email' => 'therapist@rehabplus.com', 'role' => 'therapist']);
    }
}
