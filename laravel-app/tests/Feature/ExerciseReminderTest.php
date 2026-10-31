<?php

namespace Tests\Feature;

use App\Services\Patient\ExerciseReminderService;
use App\Services\Patient\PatientProgress;
use App\Services\Patient\PrescriptionService;
use Carbon\CarbonImmutable;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/**
 * Evening exercise reminders: who is due, the cron route's guards, and the
 * notification + push each due patient gets (once a day at most).
 */
class ExerciseReminderTest extends TestCase
{
    use FakeFirebase;

    private const SECRET = 'test-cron-secret';

    /** Wednesday 21 Oct 2026, 6:30 PM in Manila (isoWeekday 3). */
    private CarbonImmutable $evening;

    protected function setUp(): void
    {
        parent::setUp();
        config(['services.reminders.cron_secret' => self::SECRET, 'services.reminders.timezone' => 'Asia/Manila']);

        $this->evening = CarbonImmutable::parse('2026-10-21 18:30', 'Asia/Manila');
        CarbonImmutable::setTestNow($this->evening);

        // pDue: Mon/Wed/Fri knee extensions, not done today.
        $this->patientDoc('pDue', ['name' => 'Dee Due', 'therapistId' => 'thA']);
        $this->docs['patients/pDue/prescriptions/rx1'] = $this->rx('kneeExtension', days: [1, 3, 5]);
        $this->docs['patients/pDue/devices/tok1'] = ['token' => 'tok1'];

        // pDone: same plan, already did it this morning.
        $this->patientDoc('pDone', ['name' => 'Don Done']);
        $this->docs['patients/pDone/prescriptions/rx2'] = $this->rx('kneeExtension', days: [3]);
        $this->docs['patients/pDone/sessions/s1'] = $this->sessionDoc('rx2', $this->evening->setTime(8, 0));
        $this->docs['patients/pDone/devices/tok2'] = ['token' => 'tok2'];

        // pArchived: would be due, but archived.
        $this->patientDoc('pArchived', ['name' => 'Old Patient', 'archived' => true]);
        $this->docs['patients/pArchived/prescriptions/rx3'] = $this->rx('bicepCurl', days: [3]);
    }

    protected function tearDown(): void
    {
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    private function rx(string $type, array $days = [], int $perWeek = 3, bool $active = true): array
    {
        return [
            'exerciseType' => $type, 'targetReps' => 10, 'frequencyPerWeek' => $perWeek,
            'schedule' => $days ? ['days' => $days, 'startHour' => null, 'endHour' => null] : null,
            'active' => $active,
        ];
    }

    private function sessionDoc(string $rxId, CarbonImmutable $start, bool $endedEarly = false): array
    {
        return ['exerciseId' => 'kneeExtension', 'prescriptionId' => $rxId, 'startTime' => $start->utc(), 'completedReps' => 10, 'painLevel' => 1, 'endedEarly' => $endedEarly];
    }

    private function callCron(?string $token = self::SECRET, string $query = '')
    {
        $headers = $token === null ? [] : ['Authorization' => "Bearer {$token}"];

        return $this->postJson('/cron/exercise-reminders'.$query, [], $headers);
    }

    // ---- who is due (pure) --------------------------------------------------

    private function presented(array $rx, string $id): array
    {
        return PrescriptionService::present($rx + ['_id' => $id]);
    }

    private function presentedSession(array $s, string $id = 's'): array
    {
        return PatientProgress::presentSession($s + ['_id' => $id, '_path' => "patients/p/sessions/{$id}"]);
    }

    public function test_scheduled_days_decide_whether_it_is_due_today(): void
    {
        $wedOnly = $this->presented($this->rx('kneeExtension', days: [3]), 'a');
        $monOnly = $this->presented($this->rx('kneeExtension', days: [1]), 'b');

        $due = ExerciseReminderService::dueToday([$wedOnly, $monOnly], [], $this->evening);

        $this->assertSame(['a'], array_column($due, 'id'));
    }

    public function test_done_today_is_not_due_but_an_ended_early_session_does_not_count(): void
    {
        $rx = $this->presented($this->rx('kneeExtension', days: [3]), 'a');

        $early = $this->presentedSession($this->sessionDoc('a', $this->evening->setTime(9, 0), endedEarly: true));
        $this->assertCount(1, ExerciseReminderService::dueToday([$rx], [$early], $this->evening));

        $done = $this->presentedSession($this->sessionDoc('a', $this->evening->setTime(9, 0)));
        $this->assertCount(0, ExerciseReminderService::dueToday([$rx], [$done], $this->evening));
    }

    public function test_yesterday_late_evening_in_manila_is_not_today(): void
    {
        $rx = $this->presented($this->rx('kneeExtension', days: [3]), 'a');
        // 11:30 PM Tuesday in Manila is 15:30 UTC Tuesday; still "yesterday".
        $yesterday = $this->presentedSession($this->sessionDoc('a', CarbonImmutable::parse('2026-10-20 23:30', 'Asia/Manila')));

        $this->assertCount(1, ExerciseReminderService::dueToday([$rx], [$yesterday], $this->evening));
    }

    public function test_any_day_plans_are_due_until_the_weekly_target_is_met(): void
    {
        $rx = $this->presented($this->rx('kneeExtension', perWeek: 2), 'a');
        $monday = $this->presentedSession($this->sessionDoc('a', CarbonImmutable::parse('2026-10-19 10:00', 'Asia/Manila')), 's1');
        $tuesday = $this->presentedSession($this->sessionDoc('a', CarbonImmutable::parse('2026-10-20 10:00', 'Asia/Manila')), 's2');
        $lastSunday = $this->presentedSession($this->sessionDoc('a', CarbonImmutable::parse('2026-10-18 10:00', 'Asia/Manila')), 's3');

        $this->assertCount(1, ExerciseReminderService::dueToday([$rx], [$monday, $lastSunday], $this->evening), 'last week does not count');
        $this->assertCount(0, ExerciseReminderService::dueToday([$rx], [$monday, $tuesday], $this->evening));
    }

    public function test_stopped_prescriptions_are_never_due(): void
    {
        $rx = $this->presented($this->rx('kneeExtension', days: [3], active: false), 'a');

        $this->assertSame([], ExerciseReminderService::dueToday([$rx], [], $this->evening));
    }

    public function test_message_names_the_exercises(): void
    {
        $one = [['exerciseName' => 'Knee Extension']];
        $three = [['exerciseName' => 'Knee Extension'], ['exerciseName' => 'Bicep Curl'], ['exerciseName' => 'Side Raise']];

        $this->assertStringContainsString("You haven't done Knee Extension today yet.", ExerciseReminderService::message($one));
        $this->assertSame('You still have 3 exercises to do today: Knee Extension, Bicep Curl and Side Raise.', ExerciseReminderService::message($three));
    }

    // ---- the cron route ----------------------------------------------------

    public function test_route_refuses_when_no_secret_is_configured(): void
    {
        config(['services.reminders.cron_secret' => '']);

        $this->callCron('anything')->assertStatus(503);
        $this->assertSame([], $this->commits);
    }

    public function test_route_refuses_a_missing_or_wrong_secret(): void
    {
        $this->callCron(null)->assertStatus(401);
        $this->callCron('wrong')->assertStatus(401);
        $this->assertSame([], $this->commits);
        $this->assertSame([], $this->pushes);
    }

    public function test_route_refuses_to_run_before_six_pm_manila(): void
    {
        CarbonImmutable::setTestNow(CarbonImmutable::parse('2026-10-21 17:59', 'Asia/Manila'));

        $this->callCron()->assertStatus(409)->assertJsonPath('now', '2026-10-21T17:59:00+08:00');
        $this->assertSame([], $this->commits);
    }

    public function test_due_patients_get_one_notification_and_push(): void
    {
        $this->callCron()->assertOk()->assertJson([
            'date' => '2026-10-21', 'patients' => 2, 'due' => 1, 'sent' => 1, 'alreadySent' => 0, 'failed' => 0, 'dryRun' => false,
        ]);

        $entry = $this->docs['patients/pDue/notifications/reminder-2026-10-21'] ?? null;
        $this->assertNotNull($entry, 'fixed id per day');
        $this->assertSame('reminder', $entry['type']);
        $this->assertSame('Exercise reminder', $entry['title']);
        $this->assertStringContainsString('Knee Extension', $entry['body']);
        $this->assertFalse($entry['read']);
        $this->assertSame(['exists' => false], $this->commits[0][0]['currentDocument']);

        $this->assertCount(1, $this->pushes);
        $this->assertSame(['type' => 'reminder'], $this->pushes[0]['data']);
        $this->assertSame('tok1', $this->pushes[0]['token']);

        $this->assertSame([], $this->docsLike('patients/pDone/notifications/*'), 'already exercised today');
        $this->assertSame([], $this->docsLike('patients/pArchived/notifications/*'), 'archived');
    }

    public function test_a_second_run_the_same_day_sends_nothing(): void
    {
        $this->callCron()->assertOk();
        $this->callCron()->assertOk()->assertJson(['due' => 1, 'sent' => 0, 'alreadySent' => 1]);

        $this->assertCount(1, $this->commits);
        $this->assertCount(1, $this->pushes);
    }

    public function test_opted_out_patients_still_get_the_entry_but_no_push(): void
    {
        $this->docs['patients/pDue/preferences/notifications'] = ['messages' => true, 'exercises' => true, 'reminders' => false];

        $this->callCron()->assertOk()->assertJson(['sent' => 1]);

        $this->assertArrayHasKey('patients/pDue/notifications/reminder-2026-10-21', $this->docs);
        $this->assertCount(0, $this->pushes);
    }

    public function test_dry_run_counts_but_writes_and_pushes_nothing(): void
    {
        $this->callCron(query: '?dry_run=1')->assertOk()->assertJson(['due' => 1, 'sent' => 0, 'dryRun' => true]);

        $this->assertSame([], $this->commits);
        $this->assertSame([], $this->pushes);
    }

    public function test_firestore_outage_gives_a_503_not_a_500(): void
    {
        $this->injectedFailures = [':runQuery' => ['connection', 'connection', 'connection']];

        $this->callCron()->assertStatus(503);
    }

    public function test_artisan_command_dry_run(): void
    {
        $this->artisan('rehab:send-reminders', ['--dry-run' => true])->assertSuccessful();
        $this->assertSame([], $this->commits);
    }
}
