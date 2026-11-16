<?php

namespace Tests\Feature;

use Carbon\CarbonImmutable;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** The landing page's "Visit us" card: today's hours, the open-now status, and the quick actions. */
class VisitUsTest extends TestCase
{
    use FakeFirebase;

    protected function tearDown(): void
    {
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    /** 16 November 2026 is a Monday; 15 November is a Sunday (Philippine time). */
    private function at(string $when): void
    {
        CarbonImmutable::setTestNow(CarbonImmutable::parse($when, config('app.timezone')));
    }

    public function test_it_says_open_now_with_the_closing_time_during_weekday_hours(): void
    {
        $this->at('2026-11-16 10:00');

        $this->get('/')->assertOk()
            ->assertSee('data-visit-status="open"', false)
            ->assertSee('Open now · closes 6:00pm')
            ->assertSee('Today');
    }

    public function test_it_says_closed_and_when_it_opens_before_the_day_starts(): void
    {
        $this->at('2026-11-16 08:00');

        $this->get('/')->assertOk()
            ->assertSee('data-visit-status="closed"', false)
            ->assertSee('Closed now · opens 9:00am today');
    }

    public function test_it_says_closed_after_hours_on_sunday(): void
    {
        $this->at('2026-11-15 20:00');

        $this->get('/')->assertOk()
            ->assertSee('data-visit-status="closed"', false)
            ->assertSee('Closed now');
    }

    public function test_the_visit_card_has_the_before_you_come_mascot_and_no_embedded_map(): void
    {
        $this->get('/')->assertOk()
            ->assertSee('Before you come')
            ->assertSee('visit-mascot', false)
            ->assertDontSee('output=embed', false)
            ->assertDontSee('data-visit-map', false);
    }

    public function test_the_health_services_section_points_to_the_clinics_services(): void
    {
        $this->get('/')->assertOk()
            ->assertSee('Health services for your recovery')
            ->assertSee('Physical therapy')
            ->assertSee('Pilatherapy')
            ->assertSee('Clinical Pilates, one-on-one')
            ->assertSee('Remote monitoring')
            ->assertSee('href="http://localhost#packages"', false)
            ->assertSee('href="http://localhost/remote-monitoring"', false);
    }

    public function test_the_landing_page_has_the_reading_progress_and_the_heartbeat_under_the_nav(): void
    {
        $this->get('/')->assertOk()
            ->assertSee('data-rehab-progress', false)
            ->assertSee('rehab-nav-indicator', false)
            ->assertSee('<script nonce="', false);
    }

    public function test_the_quick_actions_link_to_the_map_the_phone_and_email(): void
    {
        $this->get('/')->assertOk()
            ->assertSee('href="https://maps.app.goo.gl/ftDwzQCMAVh1mfXE9"', false)
            ->assertSee('Get directions')
            ->assertDontSee('tel:', false) // the public page has no tap-to-call links
            ->assertDontSee('Message on Facebook') // the contact tile has no button
            ->assertSee('to=rehabplusphysiotherapy24%40gmail.com', false)
            ->assertSee('Send an email');
    }
}
