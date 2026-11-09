<?php

namespace Tests\Feature;

use App\Services\Dashboard\DailyInsightsService;
use Carbon\CarbonImmutable;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** The greeting card at the top of the dashboard. */
class DailyInsightsTest extends TestCase
{
    use FakeFirebase;

    private CarbonImmutable $now;

    protected function setUp(): void
    {
        parent::setUp();

        $this->now = CarbonImmutable::now(config('app.timezone'));
        $this->staff('admin', 'adm1', 'Front Desk');
        $this->staff('therapist', 'thA', 'Dr. Lee');
        $this->staff('therapist', 'thB', 'Dr. Ben');
    }

    public function test_admin_sees_todays_new_patients_and_accounts(): void
    {
        $this->patientDoc('pNew1', ['name' => 'New One', 'therapistId' => 'thA', 'createdAt' => $this->now]);
        $this->patientDoc('pNew2', ['name' => 'New Two', 'therapistId' => 'thB', 'createdAt' => $this->now]);
        $this->patientDoc('pOld', ['name' => 'Old Patient', 'therapistId' => 'thB', 'createdAt' => $this->now->subDays(10)]);
        $this->staff('therapist', 'thNew', 'Dr. New');
        $this->docs['users/thNew']['createdAt'] = $this->now;

        $response = $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'))->get('/dashboard')->assertOk()
            ->assertSee('Hello, Front Desk!')
            ->assertSee('For your information, today we have 2 new patients and 1 new staff account created.');

        $daily = $response->viewData('daily');
        $this->assertSame(2, $daily['newPatients']);
        $this->assertSame(1, $daily['newStaff']);
    }

    public function test_no_new_accounts_today_says_so(): void
    {
        $this->patientDoc('pOld', ['name' => 'Old Patient', 'createdAt' => $this->now->subDays(10)]);

        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'))->get('/dashboard')->assertOk()
            ->assertSee('No new patients or accounts have been created yet today.');
    }

    public function test_therapist_counts_only_their_own_patients_and_no_staff(): void
    {
        $this->patientDoc('pMine', ['name' => 'Mine', 'therapistId' => 'thA', 'createdAt' => $this->now]);
        $this->patientDoc('pTheirs', ['name' => 'Theirs', 'therapistId' => 'thB', 'createdAt' => $this->now]);

        $response = $this->actingAs($this->staff('therapist', 'thA', 'Dr. Lee'))->get('/dashboard')->assertOk()
            ->assertSee('Hello, Dr. Lee!')
            ->assertSee('today we have 1 new patient created.')
            ->assertDontSee('New staff accounts');

        $this->assertNull($response->viewData('daily')['newStaff']);
        $this->assertSame(1, $response->viewData('daily')['newPatients']);
    }

    public function test_only_the_greeting_card_is_shown_no_glance_tiles_or_insights(): void
    {
        $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'))->get('/dashboard')->assertOk()
            ->assertSee('daily-hero')
            ->assertDontSee('Today at a glance')
            ->assertDontSee('Insights for today')
            ->assertDontSee('daily-tile');
    }

    public function test_greeting_and_icon_follow_the_time_of_day(): void
    {
        $this->assertSame(['Good evening', 'bi-moon-stars-fill'], DailyInsightsService::greeting(1));
        $this->assertSame(['Good evening', 'bi-moon-stars-fill'], DailyInsightsService::greeting(4));
        $this->assertSame(['Good morning', 'bi-sunrise-fill'], DailyInsightsService::greeting(5));
        $this->assertSame(['Good morning', 'bi-sunrise-fill'], DailyInsightsService::greeting(11));
        $this->assertSame(['Good afternoon', 'bi-sun-fill'], DailyInsightsService::greeting(12));
        $this->assertSame(['Good afternoon', 'bi-sun-fill'], DailyInsightsService::greeting(17));
        $this->assertSame(['Good evening', 'bi-moon-stars-fill'], DailyInsightsService::greeting(18));
        $this->assertSame(['Good evening', 'bi-moon-stars-fill'], DailyInsightsService::greeting(23));
    }

    public function test_the_hero_shows_the_icon_for_the_clinic_hour(): void
    {
        $response = $this->actingAs($this->staff('admin', 'adm1', 'Front Desk'))->get('/dashboard')->assertOk();
        [, $icon] = DailyInsightsService::greeting(CarbonImmutable::now(config('app.timezone'))->hour);

        $response->assertSee($icon, false);
        $this->assertSame($icon, $response->viewData('daily')['greetingIcon']);
    }

    public function test_summary_line_wording(): void
    {
        $this->assertSame('No new patients or accounts have been created yet today.', DailyInsightsService::summaryLine(0, 0));
        $this->assertSame('For your information, today we have 1 new patient created.', DailyInsightsService::summaryLine(1, null));
        $this->assertSame('For your information, today we have 1 new patient and 2 new staff accounts created.', DailyInsightsService::summaryLine(1, 2));
        $this->assertSame('For your information, today we have 2 new staff accounts created.', DailyInsightsService::summaryLine(0, 2));
    }
}
