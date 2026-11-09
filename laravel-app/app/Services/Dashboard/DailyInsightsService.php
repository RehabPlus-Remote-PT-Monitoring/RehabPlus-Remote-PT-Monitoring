<?php

namespace App\Services\Dashboard;

use App\Auth\StaffUser;
use App\Services\Firebase\FirebaseException;
use App\Services\User\StaffDirectory;
use App\Services\User\UserService;
use Carbon\CarbonImmutable;

/**
 * The greeting card at the top of the dashboard: "Hello, {name}", the date, what
 * was created today, and a quote of the day. The new-account counts come from
 * data the dashboard already has, plus one staff list read for administrators.
 */
class DailyInsightsService
{
    /** Short encouragements, one per day in rotation. */
    public const QUOTES = [
        'Small steps every day add up to big recovery.',
        'Consistency beats intensity. Every check-in counts.',
        'A kind word and a clear plan can change a whole week for a patient.',
        'Progress is quiet at first. Keep showing up for your patients.',
        'Good care is built one session, one note, and one reply at a time.',
        'Your patients trust you. Thank you for the care you give today.',
        'Celebrate the small wins. They keep patients motivated.',
    ];

    public function __construct(private UserService $users, private StaffDirectory $directory)
    {
    }

    /**
     * @param  array  $overview  the dashboard overview (patientStats)
     * @return array<string, mixed>|null null when Firebase can't be reached; the card is then left out
     */
    public function build(StaffUser $user, array $overview): ?array
    {
        $tz = config('app.timezone');
        $now = CarbonImmutable::now($tz);
        $today = $now->toDateString();
        $isAdmin = $user->isAdmin();

        try {
            $staffAccounts = $isAdmin ? $this->users->staff() : [];
        } catch (FirebaseException $e) {
            report($e);

            return null;
        }

        $newPatients = count(array_filter($overview['patientStats'], fn (array $p) => $this->isToday($p['created_at'] ?? null, $tz, $today)));
        $newStaff = $isAdmin
            ? count(array_filter($staffAccounts, fn (array $u) => $this->isToday($u['createdAt'] ?? null, $tz, $today)))
            : null;

        [$greeting, $greetingIcon] = self::greeting($now->hour);

        return [
            'greeting' => $greeting,
            'greetingIcon' => $greetingIcon,
            'name' => $this->directory->name($user->id, $user->name) ?: 'there',
            'dateLabel' => $now->format('l, F j, Y'),
            'newPatients' => $newPatients,
            'newStaff' => $newStaff,
            'summary' => self::summaryLine($newPatients, $newStaff),
            'quote' => self::QUOTES[$now->dayOfYear % count(self::QUOTES)],
        ];
    }

    /** The "for your information" sentence. */
    public static function summaryLine(int $newPatients, ?int $newStaff): string
    {
        $parts = [];
        if ($newPatients > 0) {
            $parts[] = $newPatients.' new patient'.($newPatients === 1 ? '' : 's');
        }
        if ($newStaff !== null && $newStaff > 0) {
            $parts[] = $newStaff.' new staff account'.($newStaff === 1 ? '' : 's');
        }

        if ($parts === []) {
            return 'No new patients or accounts have been created yet today.';
        }

        return 'For your information, today we have '.self::joinWords($parts).' created.';
    }

    /**
     * The greeting and its icon for an hour (0-23, clinic time): morning from 5 AM,
     * afternoon from noon, evening from 6 PM through the night.
     *
     * @return array{0: string, 1: string}
     */
    public static function greeting(int $hour): array
    {
        return match (true) {
            $hour >= 5 && $hour < 12 => ['Good morning', 'bi-sunrise-fill'],
            $hour >= 12 && $hour < 18 => ['Good afternoon', 'bi-sun-fill'],
            default => ['Good evening', 'bi-moon-stars-fill'],
        };
    }

    private function isToday(mixed $at, string $tz, string $today): bool
    {
        return $at instanceof CarbonImmutable && $at->setTimezone($tz)->toDateString() === $today;
    }

    private static function joinWords(array $parts): string
    {
        return count($parts) === 2 ? $parts[0].' and '.$parts[1] : implode(', ', $parts);
    }
}
