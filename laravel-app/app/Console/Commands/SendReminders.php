<?php

namespace App\Console\Commands;

use App\Services\Firebase\FirebaseException;
use App\Services\Patient\ExerciseReminderService;
use Illuminate\Console\Command;

/**
 * Send (or with --dry-run, just count) today's evening exercise reminders by
 * hand. The daily run normally comes from the GitHub Actions schedule calling
 * POST /cron/exercise-reminders; this skips that route's 6 PM check.
 */
class SendReminders extends Command
{
    protected $signature = 'rehab:send-reminders {--dry-run : Only report who is due; write and push nothing}';

    protected $description = 'Send today\'s exercise reminders to patients who haven\'t done their exercises';

    public function handle(ExerciseReminderService $reminders): int
    {
        try {
            $summary = $reminders->run(dryRun: (bool) $this->option('dry-run'));
        } catch (FirebaseException $e) {
            $this->error('Firebase could not be reached: '.$e->getMessage());

            return self::FAILURE;
        }

        $this->table(['date', 'patients', 'due', 'sent', 'already sent', 'failed', 'dry run'], [[
            $summary['date'], $summary['patients'], $summary['due'], $summary['sent'],
            $summary['alreadySent'], $summary['failed'], $summary['dryRun'] ? 'yes' : 'no',
        ]]);

        return $summary['failed'] > 0 ? self::FAILURE : self::SUCCESS;
    }
}
