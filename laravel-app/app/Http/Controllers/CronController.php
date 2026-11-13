<?php

namespace App\Http\Controllers;

use App\Services\Firebase\FirebaseException;
use App\Services\Patient\ExerciseReminderService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

/**
 * Scheduled jobs called from outside (Vercel has no always-on scheduler).
 * The caller proves itself with "Authorization: Bearer <CRON_SECRET>"; there
 * is no staff login on these routes.
 */
class CronController extends Controller
{
    /**
     * POST /cron/exercise-reminders[?dry_run=1]: send today's evening
     * reminders (see ExerciseReminderService). Answers JSON with the counts:
     * 200 done, 401 bad/missing secret, 409 too early in the day, 503 not
     * configured or Firebase unreachable.
     */
    public function exerciseReminders(Request $request, ExerciseReminderService $reminders): JsonResponse
    {
        $secret = (string) config('services.reminders.cron_secret');
        if ($secret === '') {
            Log::warning('cron.reminders refused: CRON_SECRET is not set');

            return response()->json(['error' => 'Reminders are not configured on this server.'], 503);
        }
        if (! hash_equals($secret, (string) $request->bearerToken())) {
            Log::warning('cron.reminders refused: bad secret', ['ip' => $request->ip()]);

            return response()->json(['error' => 'Unauthorized.'], 401);
        }

        // GitHub's scheduler can start early or late; never remind before the
        // evening, when a patient may still be planning to exercise.
        $now = CarbonImmutable::now()->setTimezone(ExerciseReminderService::timezone());
        $after = (int) config('services.reminders.send_after_hour', 18);
        if ($now->hour < $after) {
            return response()->json([
                'error' => "Too early: reminders go out from {$after}:00 ".ExerciseReminderService::timezone().'.',
                'now' => $now->toIso8601String(),
            ], 409);
        }

        try {
            $summary = $reminders->run($now, dryRun: $request->boolean('dry_run'));
        } catch (FirebaseException $e) {
            Log::error('cron.reminders failed', ['error' => $e->getMessage()]);

            return response()->json(['error' => 'Firebase could not be reached. Try again later.'], 503);
        }

        return response()->json($summary);
    }
}
