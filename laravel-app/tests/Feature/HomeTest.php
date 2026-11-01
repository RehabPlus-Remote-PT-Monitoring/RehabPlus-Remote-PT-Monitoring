<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Config;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** The Home page: clinic details from config/clinic.php and the staff board from Firestore users. */
class HomeTest extends TestCase
{
    use FakeFirebase;

    public function test_guests_are_sent_to_login(): void
    {
        $this->get('/home')->assertRedirect('/login');
    }

    public function test_home_is_the_first_link_in_the_navigation(): void
    {
        $this->actingAs($this->staff('admin'))->get('/home')->assertOk()
            ->assertSee('href="http://localhost/home"', false)
            ->assertSee('class="nav-link active" href="http://localhost/home"', false);
    }

    public function test_home_shows_clinic_details_and_the_facebook_button(): void
    {
        $this->actingAs($this->staff('admin'))->get('/home')->assertOk()
            ->assertSee('Rehab Plus Physiotherapy')
            ->assertSee('Physical Therapy + Clinical Pilates')
            ->assertSee('Monday to Saturday')
            ->assertSee('9:00am – 6:00pm')
            ->assertSee('Sunday')
            ->assertSee('1308 Benavidez St, Metro Manila')
            ->assertSee('href="tel:09128548156"', false)
            ->assertSee('href="mailto:rehabplusphysiotherapy24@gmail.com"', false)
            ->assertSee('href="https://www.facebook.com/profile.php?id=61577141983895"', false)
            ->assertSee('assets/images/rehab-logo.jpg', false)
            ->assertSee('assets/images/pt.jpg', false);
    }

    public function test_staff_board_lists_active_staff_by_role_and_skips_disabled_accounts(): void
    {
        $this->staff('staff', 'st1', 'Sam Front');
        $this->staff('therapist', 'thA', 'Dr. Ana');
        $this->staff('therapist', 'thOld', 'Dr. Gone');
        $this->docs['users/thOld']['active'] = false;

        $response = $this->actingAs($this->staff('admin', 'adm1', 'Ada Admin'))->get('/home')->assertOk()
            ->assertSee('Ada Admin')
            ->assertSee('Dr. Ana')
            ->assertSee('Sam Front')
            ->assertSee('Administrator')
            ->assertSee('Physical Therapist')
            ->assertSee('Front Desk Staff')
            ->assertDontSee('Dr. Gone');

        $html = $response->getContent();
        $this->assertLessThan(strpos($html, 'Dr. Ana'), strpos($html, 'Ada Admin'), 'admins are listed before therapists');
        $this->assertLessThan(strpos($html, 'Sam Front'), strpos($html, 'Dr. Ana'), 'therapists are listed before front desk');
    }

    public function test_staff_photos_are_used_only_from_firebase_storage(): void
    {
        $this->staff('therapist', 'thA', 'Dr. Ana');
        $this->staff('staff', 'st1', 'Sam Front');
        $this->docs['users/thA']['photoUrl'] = 'https://firebasestorage.googleapis.com/v0/b/clinic/o/ana.jpg?alt=media';
        $this->docs['users/st1']['photoUrl'] = 'javascript:alert(1)';

        $this->actingAs($this->staff('admin'))->get('/home')->assertOk()
            ->assertSee('src="https://firebasestorage.googleapis.com/v0/b/clinic/o/ana.jpg?alt=media"', false)
            ->assertDontSee('javascript:alert', false);
    }

    public function test_staff_photo_from_this_sites_staff_folder_is_used(): void
    {
        $this->staff('therapist', 'thA', 'Dr. Ana');
        $this->staff('staff', 'st1', 'Sam Front');
        $this->docs['users/thA']['photoUrl'] = '/assets/images/staff/thA.jpg';
        $this->docs['users/st1']['photoUrl'] = '/assets/images/../../.env';

        $this->actingAs($this->staff('admin'))->get('/home')->assertOk()
            ->assertSee('src="/assets/images/staff/thA.jpg"', false)
            ->assertDontSee('.env', false);
    }

    public function test_awards_show_when_added_and_an_empty_state_otherwise(): void
    {
        $this->actingAs($this->staff('admin'))->get('/home')->assertOk()
            ->assertSee('No awards added yet');

        Config::set('clinic.awards', [
            ['title' => 'Best Physical Therapy Clinic', 'issuer' => 'Physio Board', 'year' => '2026'],
        ]);

        $this->get('/home')->assertOk()
            ->assertSee('Best Physical Therapy Clinic')
            ->assertSee('Physio Board')
            ->assertSee('2026')
            ->assertDontSee('No awards added yet');
    }
}
