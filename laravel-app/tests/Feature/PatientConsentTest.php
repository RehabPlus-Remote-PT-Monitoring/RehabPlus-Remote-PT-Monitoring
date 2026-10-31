<?php

namespace Tests\Feature;

use App\Services\Patient\ConsentService;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Log;
use Mockery;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/**
 * Terms / Privacy Policy consent status on the patient profile
 * (patients/{uid}/consents/{version}, written by the app, read-only here).
 */
class PatientConsentTest extends TestCase
{
    use FakeFirebase;

    protected function setUp(): void
    {
        parent::setUp();

        config(['services.legal.consent_version' => '2026-10-18']);
        $this->patientDoc('pOne', ['name' => 'Olive One', 'therapistId' => 'thA', 'therapistName' => 'Dr. Ana']);
    }

    private function therapist()
    {
        return $this->staff('therapist', 'thA', 'Dr. Ana');
    }

    /** A consent document the way the app writes it. */
    private function consent(string $version, CarbonImmutable $acceptedAt, array $overrides = []): void
    {
        $this->docs["patients/pOne/consents/{$version}"] = $overrides + [
            'version' => $version,
            'acceptedTerms' => true,
            'acceptedPrivacyPolicy' => true,
            'healthDataConsent' => true,
            'cameraConsent' => true,
            'acceptedAt' => $acceptedAt,
        ];
    }

    public function test_current_version_shows_version_and_date(): void
    {
        $this->consent('2026-10-18', CarbonImmutable::parse('2026-10-20 03:00', 'UTC'));

        $this->actingAs($this->therapist())->get('/patients/pOne')
            ->assertOk()
            ->assertSee('data-consent="current"', false)
            ->assertSee('Accepted terms v2026-10-18')
            ->assertSee(CarbonImmutable::parse('2026-10-20 03:00', 'UTC')->setTimezone(config('app.timezone'))->format('M j, Y'))
            ->assertSee('Health data')
            ->assertDontSee('older version')
            ->assertSee('Assigned exercises'); // clinical reads still load alongside it
    }

    public function test_newest_acceptance_wins_and_older_version_is_flagged(): void
    {
        $this->consent('2026-01-05', CarbonImmutable::parse('2026-01-06'));
        $this->consent('2026-03-01', CarbonImmutable::parse('2026-03-02'));

        $this->actingAs($this->therapist())->get('/patients/pOne')
            ->assertOk()
            ->assertSee('data-consent="outdated"', false)
            ->assertSee('Accepted terms v2026-03-01')
            ->assertDontSee('v2026-01-05')
            ->assertSee('This is an older version (current is v2026-10-18)')
            ->assertSee('asked to accept the new terms next time they open the app');
    }

    public function test_no_consent_documents_shows_not_yet_accepted(): void
    {
        $this->actingAs($this->therapist())->get('/patients/pOne')
            ->assertOk()
            ->assertSee('data-consent="none"', false)
            ->assertSee('Not yet accepted');
    }

    public function test_malformed_consent_documents_do_not_break_the_profile(): void
    {
        // Consents come from the patient's phone; a patient talking to
        // Firestore directly could store any type in any field.
        $this->docs['patients/pOne/consents/2026-10-18'] = [
            'version' => ['evil' => 'map'],
            'acceptedAt' => ['not' => 'a timestamp'],
            'acceptedTerms' => 'yes',
            'acceptedPrivacyPolicy' => ['x'],
            'healthDataConsent' => 1,
            'cameraConsent' => true,
        ];

        $this->actingAs($this->therapist())->get('/patients/pOne')
            ->assertOk()
            ->assertSee('Accepted terms v2026-10-18')   // version falls back to the doc id
            ->assertSee('on an unknown date')
            ->assertSee('Terms: not agreed')            // only a real `true` counts
            ->assertSee('Camera: agreed');
    }

    public function test_summarise_ignores_unusable_documents(): void
    {
        $status = ConsentService::summarise([
            ['_id' => str_repeat('x', 200), 'version' => 42],
            ['_id' => 'abc', 'version' => '   '],
        ]);
        // 'abc' (the id) is a usable version once the blank field is ignored.
        $this->assertSame('abc', $status['version']);

        $this->assertSame(ConsentService::NONE, ConsentService::summarise([
            ['_id' => str_repeat('x', 200), 'version' => ['a']],
        ])['status']);
    }

    public function test_front_desk_staff_see_consent_status_too(): void
    {
        $this->consent('2026-10-18', CarbonImmutable::parse('2026-10-19'));

        $this->actingAs($this->staff('staff'))->get('/patients/pOne')
            ->assertOk()
            ->assertSee('Accepted terms v2026-10-18')
            ->assertDontSee('Assigned exercises');
    }

    public function test_failed_consent_read_shows_unavailable_but_page_loads(): void
    {
        Log::spy();
        $this->consent('2026-10-18', CarbonImmutable::parse('2026-10-19'));
        // Front desk: the consent query is the only runQuery on this page.
        $this->injectedFailures[':runQuery'] = [403];

        $this->actingAs($this->staff('staff'))->get('/patients/pOne')
            ->assertOk()
            ->assertSee('Olive One')
            ->assertSee('data-consent="unavailable"', false)
            ->assertSee('Consent status unavailable');

        Log::shouldHaveReceived('warning')->with('consents.unreadable', Mockery::on(fn ($context) => $context['patient'] === 'pOne'));
    }

    public function test_failed_consent_read_does_not_fail_the_clinical_reads(): void
    {
        $this->consent('2026-10-18', CarbonImmutable::parse('2026-10-19'));
        // One non-retried failure on the first runQuery sent. The consent task
        // is listed first in the controller's concurrently() batch, so it's
        // the one that fails; sessions/prescriptions etc. still answer.
        $this->injectedFailures[':runQuery'] = [403];

        $this->actingAs($this->therapist())->get('/patients/pOne')
            ->assertOk()
            ->assertSee('Consent status unavailable')
            ->assertSee('Assigned exercises');   // a 200 means no clinical read failed
        $this->assertSame([], $this->commits);   // consents are read-only
    }
}
