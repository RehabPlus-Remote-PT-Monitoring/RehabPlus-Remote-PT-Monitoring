<?php

namespace App\Services\Patient;

use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreClient;
use App\Services\Firebase\PatientNotifier;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Log;

/**
 * The clinic's evening exercise reminder: every patient who still has
 * exercises due today and hasn't done them gets one entry on the app's
 * Notifications page plus a push (data.type 'reminder').
 *
 * Triggered once a day at 6 PM Manila time by a GitHub Actions schedule that
 * calls POST /cron/exercise-reminders (see CronController), or by hand with
 * `php artisan rehab:send-reminders`.
 *
 * "Due today" for an active prescription, in the clinic's time zone:
 *   - it has schedule days: today is one of them;
 *   - it has no days ("any day"): fewer completed sessions this week
 *     (Monday to now) than its frequencyPerWeek.
 * It is "done" once a session for that prescription started today and wasn't
 * ended early. Archived patients are skipped.
 *
 * Each patient gets at most one reminder per day: the notification doc id is
 * "reminder-YYYY-MM-DD", created with an "must not exist" precondition, so a
 * second run that day (a retried Action, a manual run) sends nothing.
 */
class ExerciseReminderService
{
    public const TYPE = 'reminder';

    public const TITLE = 'Exercise reminder';

    /** How many recent sessions per patient are enough to cover this week. */
    private const RECENT_SESSIONS = 60;

    public function __construct(
        private FirestoreClient $db,
        private PatientNotifier $notifier,
    ) {
    }

    /** The clinic's time zone; reminders and "today" follow it. */
    public static function timezone(): string
    {
        return (string) config('services.reminders.timezone', 'Asia/Manila');
    }

    /**
     * Send today's reminders.
     *
     * @param  bool  $dryRun  work out who is due but write and push nothing
     * @return array{date: string, patients: int, due: int, sent: int, alreadySent: int, failed: int, dryRun: bool}
     */
    public function run(?CarbonImmutable $now = null, bool $dryRun = false): array
    {
        $now = ($now ?? CarbonImmutable::now())->setTimezone(self::timezone());
        $date = $now->format('Y-m-d');

        $patients = array_values(array_filter(
            $this->db->query('', 'patients'),
            fn ($p) => ! ($p['archived'] ?? false),
        ));

        // Each patient's active prescriptions and recent sessions, all read in parallel.
        $tasks = [];
        foreach ($patients as $patient) {
            $uid = $patient['_id'];
            $tasks["{$uid}|rx"] = fn () => $this->db->query("patients/{$uid}", 'prescriptions', [['active', 'EQUAL', true]]);
            $tasks["{$uid}|sessions"] = fn () => $this->db->query(
                "patients/{$uid}", 'sessions', orderBy: ['startTime', 'DESCENDING'], limit: self::RECENT_SESSIONS,
            );
        }
        $results = $tasks === [] ? [] : $this->db->concurrently($tasks);

        $summary = ['date' => $date, 'patients' => count($patients), 'due' => 0, 'sent' => 0, 'alreadySent' => 0, 'failed' => 0, 'dryRun' => $dryRun];

        foreach ($patients as $patient) {
            $uid = $patient['_id'];
            $prescriptions = array_map([PrescriptionService::class, 'present'], $results["{$uid}|rx"] ?? []);
            $sessions = array_map([PatientProgress::class, 'presentSession'], $results["{$uid}|sessions"] ?? []);

            $due = self::dueToday($prescriptions, $sessions, $now);
            if ($due === []) {
                continue;
            }
            $summary['due']++;
            if ($dryRun) {
                continue;
            }

            $outcome = $this->remind($uid, $date, $due);
            $summary[$outcome]++;
        }

        Log::info('reminders.run', $summary);

        return $summary;
    }

    /**
     * The prescriptions still to do today. Pure, so it is unit-tested directly.
     *
     * @param  array  $prescriptions  PrescriptionService::present() shape
     * @param  array  $sessions  PatientProgress::presentSession() shape
     * @param  CarbonImmutable  $now  in the clinic's time zone
     * @return array the due prescriptions, in the given order
     */
    public static function dueToday(array $prescriptions, array $sessions, CarbonImmutable $now): array
    {
        $tz = $now->getTimezone();
        $today = $now->startOfDay();
        $weekStart = $now->startOfWeek(CarbonImmutable::MONDAY);

        $completedFor = function (string $rxId, CarbonImmutable $since) use ($sessions, $tz): int {
            return count(array_filter($sessions, fn ($s) => $s['prescriptionId'] === $rxId
                && ! $s['endedEarly']
                && $s['startTime'] !== null
                && $s['startTime']->setTimezone($tz)->greaterThanOrEqualTo($since)));
        };

        $due = [];
        foreach ($prescriptions as $rx) {
            if (! $rx['active']) {
                continue;
            }
            if ($completedFor($rx['id'], $today) > 0) {
                continue; // already done today
            }

            $days = $rx['days'] ?? [];
            $isDue = $days !== []
                ? in_array($now->isoWeekday(), $days, true)
                : $completedFor($rx['id'], $weekStart) < max(1, $rx['frequencyPerWeek']);

            if ($isDue) {
                $due[] = $rx;
            }
        }

        return $due;
    }

    /** "Knee Extension", "Knee Extension and Bicep Curl", "A, B and C". */
    public static function message(array $due): string
    {
        $names = array_values(array_unique(array_column($due, 'exerciseName')));
        $list = count($names) > 1
            ? implode(', ', array_slice($names, 0, -1)).' and '.end($names)
            : ($names[0] ?? 'your exercises');

        return count($due) === 1
            ? "You haven't done {$list} today yet. A few minutes now keeps your recovery on track."
            : 'You still have '.count($due)." exercises to do today: {$list}.";
    }

    /** @return 'sent'|'alreadySent'|'failed' */
    private function remind(string $uid, string $date, array $due): string
    {
        $body = self::message($due);
        $write = $this->notifier->notificationWrite($uid, self::TYPE, self::TITLE, $body);
        // A fixed id per day, so the create-precondition stops a second reminder.
        $write['update']['name'] = $this->db->name("patients/{$uid}/notifications/reminder-{$date}");

        try {
            if ($this->db->get("patients/{$uid}/notifications/reminder-{$date}") !== null) {
                return 'alreadySent';
            }
            $this->db->commit([$write]);
        } catch (FirebaseException $e) {
            // Another run created it in between, or Firestore is down: either way no push.
            Log::warning('reminders.not_saved', ['patient' => $uid, 'error' => $e->getMessage()]);

            return 'failed';
        }

        $this->notifier->push($uid, self::TITLE, $body, ['type' => self::TYPE]);

        return 'sent';
    }
}
