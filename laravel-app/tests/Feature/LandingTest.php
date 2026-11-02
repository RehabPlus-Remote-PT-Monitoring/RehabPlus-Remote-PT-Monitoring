<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Config;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** The public welcome page at the site root: clinic details and team, no private information. */
class LandingTest extends TestCase
{
    use FakeFirebase;

    public function test_guests_see_the_clinic_details_and_the_facebook_link(): void
    {
        $this->get('/')->assertOk()
            ->assertSee('Rehab Plus Physiotherapy')
            ->assertSee('Physical Therapy + Clinical Pilates')
            ->assertSee('1308 Benavidez St, Metro Manila')
            ->assertSee('0912 854 8156')
            ->assertSee('href="https://maps.app.goo.gl/ftDwzQCMAVh1mfXE9"', false)
            ->assertDontSee('tel:', false)
            ->assertSee('https://mail.google.com/mail/?view=cm&amp;fs=1&amp;to=rehabplusphysiotherapy24%40gmail.com', false)
            ->assertSee('href="https://www.facebook.com/profile.php?id=61577141983895"', false)
            ->assertSee('href="https://www.instagram.com/rehabplus.physiotherapy"', false)
            ->assertSee('pilates-packages.png', false)
            ->assertSee('rehab-packages.png', false)
            ->assertSee('id="packages"', false)
            ->assertSee('id="about"', false)
            ->assertSee('About Rehab+')
            ->assertSee('movement-focused physical therapy clinic and Pilates studio')
            ->assertSee('href="http://localhost#about"', false)
            ->assertSee('Recognitions &amp; Rewards', false)
            ->assertDontSee('data-section="rewards"', false);
    }

    public function test_remote_monitoring_is_prescription_only_and_has_no_public_download_or_registration(): void
    {
        $html = $this->get('/')->assertOk()
            ->assertSee('RehabPlus Remote Monitoring')
            ->assertSee('prescription-only tool')
            ->assertSee('enrolled in a rehabilitation package')
            ->assertSee('AI-powered real-time pose estimation')
            ->assertSee('There is no public registration')
            ->assertDontSee('Download on Android')
            ->assertDontSee('Play Store')
            ->assertSee('assets/images/app/app-home.jpg', false)
            ->assertSee('assets/images/app/app-login.jpg', false)
            ->assertSee('assets/images/app/app-exercises.jpg', false)
            ->getContent();

        $this->assertLessThan(strpos($html, 'id="patients"'), strpos($html, 'id="visit"'), 'visit comes before remote monitoring');
    }

    public function test_new_visitors_are_directed_to_book_or_contact_the_clinic(): void
    {
        $this->get('/')->assertOk()
            ->assertSee('Contact Us on Facebook')
            ->assertSee('Contact Us on Instagram')
            ->assertSee('And follow us there for more updates')
            ->assertDontSee('Book a Consultation')
            ->assertSee('0912 854 8156')
            ->assertSee('Classes')
            ->assertSee('Jumpboard Flow Class')
            ->assertSee('Pilatherapy')
            ->assertSee('assets/images/classes/pilatherapy.jpg', false);
    }

    public function test_the_footer_links_to_contact_and_the_policy_pages(): void
    {
        $this->get('/')->assertOk()
            ->assertDontSee('href="http://localhost#contact"', false)
            ->assertSee('href="http://localhost/information/faq"', false)
            ->assertSee('href="http://localhost/information/cancellation-policy"', false)
            ->assertSee('href="http://localhost/information/refund-policy"', false)
            ->assertSee('href="http://localhost/information/terms"', false)
            ->assertSee('Class Cancellation &amp; Late Arrival Policy', false);

        $this->get('/information/refund-policy')->assertOk()
            ->assertSee('Refund Policy')
            ->assertSee('strictly non-refundable, non-exchangeable and non-transferable')
            ->assertDontSee('This page is being prepared');

        $this->get('/information/faq')->assertOk()
            ->assertSee('What should I bring to my first visit?')
            ->assertSee('There is no public registration')
            ->assertSee('Mon')
            ->assertDontSee('This page is being prepared');

        $this->get('/information/terms')->assertOk()
            ->assertSee('Terms and Conditions')
            ->assertSee('Fees and Payments')
            ->assertDontSee('Rezerv')
            ->assertDontSee('Membership')
            ->assertDontSee('This page is being prepared');

        $this->get('/information/not-a-page')->assertNotFound();

        $policy = $this->get('/information/cancellation-policy')->assertOk()
            ->assertSee('Early Cancellations')
            ->assertSee('Private/Duet Late Arrivals')
            ->assertSee('Rehab+ Physiotherapy &amp; Pilates', false)
            ->getContent();
        $this->assertStringNotContainsString('Awan', $policy);
    }

    public function test_the_remote_monitoring_page_describes_the_app_and_is_linked_from_the_welcome_page(): void
    {
        $this->get('/')->assertOk()
            ->assertSee('href="http://localhost/remote-monitoring"', false)
            ->assertSee('Learn more')
            ->assertSee('RehabPlus Remote Monitoring App')
            ->assertSee('an alternative way to continue your rehabilitation');

        $this->get('/remote-monitoring')->assertOk()
            ->assertSee('How it works')
            ->assertSee('Camera-based guidance')
            ->assertSee('Real-time form feedback')
            ->assertSee('Messages with your clinic')
            ->assertSee('There is no public registration')
            ->assertSee('assets/images/app/app-home.jpg', false)
            ->assertDontSee('Download on Android');
    }

    public function test_the_staff_login_page_links_back_to_the_website(): void
    {
        $this->get(route('login.page'))->assertOk()
            ->assertSee('Rehab+ website')
            ->assertSee('href="'.route('landing').'"', false);
    }

    public function test_guests_get_no_dashboard_navigation(): void
    {
        $this->get('/')->assertOk()
            ->assertDontSee('class="sidebar', false)
            ->assertDontSee('href="http://localhost/patients"', false)
            ->assertDontSee('href="http://localhost/users"', false);
    }

    public function test_team_shows_active_staff_by_role_without_emails(): void
    {
        $this->staff('therapist', 'thA', 'Dr. Ana', 'ana@rehabplus.com');
        $this->staff('therapist', 'st1', 'Sam Front', 'sam@rehabplus.com');
        $this->staff('therapist', 'thOld', 'Dr. Gone', 'gone@rehabplus.com');
        $this->docs['users/thOld']['active'] = false;

        $this->get('/')->assertOk()
            ->assertSee('Dr. Ana')
            ->assertSee('Physical Therapist')
            ->assertSee('Sam Front')
            ->assertDontSee('Dr. Gone')
            ->assertDontSee('ana@rehabplus.com')
            ->assertDontSee('sam@rehabplus.com');
    }

    public function test_team_cards_show_the_contact_number_and_email_but_never_the_login_email(): void
    {
        $this->staff('therapist', 'thA', 'Dr. Ana', 'ana@rehabplus.com');
        $this->docs['users/thA']['contactPhone'] = '+639171234567';
        $this->docs['users/thA']['contactEmail'] = 'ana.pt@gmail.com';

        $this->get('/')->assertOk()
            ->assertSee('Dr. Ana')
            ->assertSee('+63 9171234567')
            ->assertSee('href="https://mail.google.com/mail/?view=cm&amp;fs=1&amp;to=ana.pt%40gmail.com"', false)
            ->assertSee('ana.pt@gmail.com')
            ->assertDontSee('ana@rehabplus.com')
            ->assertDontSee('href="tel:', false);
    }

    public function test_the_page_still_loads_when_firestore_is_unavailable(): void
    {
        $this->injectedFailures[':runQuery'] = [503, 503, 503];

        $this->get('/')->assertOk()
            ->assertSee('1308 Benavidez St, Metro Manila')
            ->assertSee('No staff accounts yet');
    }

    public function test_team_is_grouped_by_role_with_a_count_for_each_group(): void
    {
        $this->staff('therapist', 'st1', 'Sam Front');
        $this->staff('therapist', 'thA', 'Dr. Ana');
        $this->staff('therapist', 'thB', 'Dr. Ben');
        $this->staff('admin', 'adm1', 'Ada Admin');

        $html = $this->get('/')->assertOk()
            ->assertSee('data-team="administrator"', false)
            ->assertSee('data-team="physical-therapist"', false)
            ->assertDontSee('team-count', false)
            ->getContent();

        $this->assertLessThan(strpos($html, 'data-team="administrator"'), strpos($html, 'data-team="physical-therapist"'), 'physical therapists come first');
    }

    public function test_administrators_and_therapists_are_the_only_team_groups(): void
    {
        $this->staff('admin', 'adm1', 'Ada Admin');
        $this->staff('therapist', 'thA', 'Dr. Ana');

        $this->get('/')->assertOk()
            ->assertSee('data-team="administrator"', false)
            ->assertSee('data-team="physical-therapist"', false)
            ->assertDontSee('data-team="front-desk-staff"', false)
            ->assertDontSee('Front Desk Staff');
    }

    public function test_staff_photos_are_used_only_from_firebase_storage(): void
    {
        $this->staff('therapist', 'thA', 'Dr. Ana');
        $this->staff('therapist', 'st1', 'Sam Front');
        $this->docs['users/thA']['photoUrl'] = 'https://firebasestorage.googleapis.com/v0/b/clinic/o/ana.jpg?alt=media';
        $this->docs['users/st1']['photoUrl'] = 'javascript:alert(1)';

        $this->get('/')->assertOk()
            ->assertSee('src="https://firebasestorage.googleapis.com/v0/b/clinic/o/ana.jpg?alt=media"', false)
            ->assertDontSee('javascript:alert', false);
    }

    public function test_staff_photo_from_this_sites_staff_folder_is_used(): void
    {
        $this->staff('therapist', 'thA', 'Dr. Ana');
        $this->staff('therapist', 'st1', 'Sam Front');
        $this->docs['users/thA']['photoUrl'] = '/assets/images/staff/thA.jpg';
        $this->docs['users/st1']['photoUrl'] = '/assets/images/../../.env';

        $this->get('/')->assertOk()
            ->assertSee('src="/assets/images/staff/thA.jpg"', false)
            ->assertDontSee('.env', false);
    }

    public function test_awards_appear_on_the_welcome_page(): void
    {
        Config::set('clinic.awards', [['title' => 'Best Physical Therapy Clinic', 'year' => '2026']]);

        $this->get('/')->assertOk()->assertSee('Best Physical Therapy Clinic');
    }
}
