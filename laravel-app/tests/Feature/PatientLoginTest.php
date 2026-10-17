<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PatientLoginTest extends TestCase
{
    use RefreshDatabase;

    public function test_patient_login_page_is_removed(): void
    {
        $this->get('/patient-login')->assertNotFound();

        $this->get('/login')->assertOk()->assertDontSee('Patient portal login');
    }

    public function test_patient_cannot_log_in_through_admin_login(): void
    {
        User::create([
            'name' => 'Emily Johnson',
            'email' => 'patient@rehabplus.com',
            'password' => bcrypt('admin123'),
            'role' => 'patient',
            'is_active' => true,
        ]);

        $this->post('/login', [
            'email' => 'patient@rehabplus.com',
            'password' => 'admin123',
        ])->assertSessionHas('error');

        $this->assertGuest();
    }
}
