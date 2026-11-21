<?php

namespace App\Console\Commands;

use App\Helpers\PhoneNumber;
use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreClient;
use App\Services\Patient\PatientService;
use Illuminate\Console\Command;

/**
 * One-time catch-up: patients saved before the dashboard linked phone numbers have no
 * number on their app login, so the app's "Forgot password" text can't reach them.
 * Safe to run again. Prints patient ids only, never phone numbers.
 */
class LinkPatientPhones extends Command
{
    protected $signature = 'rehab:link-patient-phones {--dry-run : Only report what would happen; change nothing}';

    protected $description = 'Put existing patients\' mobile numbers on their app logins, for password reset texts';

    public function handle(FirestoreClient $db, PatientService $patients): int
    {
        $dryRun = (bool) $this->option('dry-run');
        $linked = 0;
        $noNumber = 0;
        $failed = 0;

        try {
            $docs = $db->query('', 'patients');
        } catch (FirebaseException $e) {
            $this->error('Firebase could not be reached: '.$e->getMessage());

            return self::FAILURE;
        }

        foreach ($docs as $doc) {
            $stored = (string) ($doc['phone'] ?? '');

            if (trim($stored) === '') {
                $noNumber++;

                continue;
            }

            $problem = $dryRun
                ? (PhoneNumber::toE164($stored) === null ? 'That phone number is not valid.' : null)
                : $patients->linkLoginPhone($doc['_id'], $stored);

            if ($problem === null) {
                $linked++;
            } else {
                $failed++;
                $this->warn("{$doc['_id']}: {$problem}");
            }
        }

        $this->table([$dryRun ? 'would link' : 'linked', 'no number', 'problems', 'dry run'], [[$linked, $noNumber, $failed, $dryRun ? 'yes' : 'no']]);

        return $failed > 0 ? self::FAILURE : self::SUCCESS;
    }
}
