<?php

namespace App\Services\StaffSchedule;

use App\Auth\StaffUser;
use App\Services\Clinic\ClinicRecord;
use App\Services\Clinic\ClinicStore;
use App\Services\Firebase\FirebaseTransport;
use App\Services\User\UserService;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/** Staff shifts and time off (Firestore `staffShifts` / `staffTimeOff`, see ClinicStore). */
class StaffScheduleService
{
    /** Roles that work shifts: therapists and front desk staff. Admins don't. */
    public const SCHEDULABLE_ROLES = [StaffUser::THERAPIST, StaffUser::STAFF];

    public function __construct(
        private ClinicStore $store,
        private ShiftConflictService $shifts,
        private UserService $users,
        private FirebaseTransport $firebase,
    ) {
    }

    public function overview(int $weekOffset): array
    {
        $weekOffset = max(-12, min(12, $weekOffset));
        $monday = CarbonImmutable::now()->startOfWeek()->addWeeks($weekOffset);
        $weekDays = collect(range(0, 6))->map(fn (int $i) => [
            'label' => $monday->addDays($i)->format('l'),
            'short' => $monday->addDays($i)->format('M j'),
        ])->all();

        // Shifts, time off and staff accounts are independent reads.
        [$schedules, $timeOff, $staffAccounts] = $this->firebase->concurrently([
            fn () => $this->store->all(ClinicStore::SHIFTS),
            fn () => $this->store->all(ClinicStore::TIME_OFF),
            fn () => $this->users->staff(),
        ]);

        $staffDirectory = $this->staffDirectory($staffAccounts);

        // Only entries that belong to someone in the directory count. An admin's (or a
        // removed account's) old entry is dropped, so it doesn't count towards today's numbers.
        $shifts = $schedules
            ->map(fn (ClinicRecord $s) => ['uid' => $this->accountUid($s, $staffDirectory), 'day' => (string) $s->day, 'shift' => (string) $s->shift, 'room' => (string) $s->room])
            ->filter(fn (array $s) => $s['uid'] !== null)
            ->sortBy('shift')
            ->values();

        $today = CarbonImmutable::today();
        $todayShifts = $shifts->where('day', $today->format('l'));
        $onLeave = $timeOff
            ->where('date', $today->toDateString())
            ->map(fn (ClinicRecord $off) => $this->accountUid($off, $staffDirectory))
            ->filter()
            ->unique()
            ->values()
            ->all();

        $staffAvailability = [];
        $todayStaffList = [];
        foreach ($staffDirectory as $staff) {
            $entries = $todayShifts->where('uid', $staff['uid'])->values();
            $status = $this->availability($entries, in_array($staff['uid'], $onLeave, true));
            $staffAvailability[$staff['uid']] = $status;
            $todayStaffList[] = [
                'name' => $staff['name'],
                'role' => $staff['roleLabel'],
                'shift' => $entries->first()['shift'] ?? 'Off',
                'room' => $entries->first()['room'] ?? 'Not assigned',
                'status' => $status,
            ];
        }

        $weeklySchedule = [];
        foreach ($shifts as $entry) {
            $weeklySchedule[$entry['uid']][$entry['day']] ??= ['shift' => $entry['shift'], 'room' => $entry['room']];
        }

        return [
            'weekOffset' => $weekOffset,
            'staffDirectory' => $staffDirectory,
            'weekDays' => $weekDays,
            'staffAvailability' => $staffAvailability,
            'weeklySchedule' => $weeklySchedule,
            'todayStaffList' => $todayStaffList,
            'staffCount' => $todayShifts->pluck('uid')->unique()->count(),
            'todayShifts' => $todayShifts->count(),
            'activeRooms' => $todayShifts->pluck('room')->filter()->unique()->count(),
        ];
    }

    /** The schedulable account with this uid (therapist or front desk, active), or null. */
    public function schedulableAccount(string $uid): ?array
    {
        return collect($this->staffDirectory($this->users->staff()))->firstWhere('uid', $uid);
    }

    public function addShift(array $shift): string
    {
        return $this->store->create(ClinicStore::SHIFTS, [
            'staffId' => $shift['staffId'],
            'staff' => $shift['staff'],
            'role' => $shift['role'],
            'day' => $shift['day'],
            'shift' => $shift['shift'],
            'room' => $shift['room'],
        ]);
    }

    public function addTimeOff(array $timeOff): string
    {
        return $this->store->create(ClinicStore::TIME_OFF, [
            'staffId' => $timeOff['staffId'],
            'staff' => $timeOff['staff'],
            'date' => CarbonImmutable::parse($timeOff['date'])->toDateString(),
            'type' => $timeOff['type'],
            'time' => $timeOff['time'],
            'reason' => $timeOff['reason'],
        ]);
    }

    /**
     * Active therapist and front desk accounts, one row per account. Each account has exactly
     * one role, the one it was created with, so two accounts with the same name are two rows.
     * Roles are an allow-list, so admins and any future role never appear here.
     */
    private function staffDirectory(array $staffAccounts): array
    {
        return collect($staffAccounts)
            ->filter(fn (array $user) => $user['active'] && in_array($user['role'], self::SCHEDULABLE_ROLES, true))
            ->sortBy(fn (array $user) => strtolower($user['name']))
            ->map(fn (array $user) => [
                'uid' => $user['uid'],
                'name' => $user['name'],
                'role' => $user['role'],
                'roleLabel' => StaffUser::ROLE_LABELS[$user['role']],
            ])
            ->values()
            ->all();
    }

    /**
     * The account a shift or time-off entry belongs to. Entries saved since accounts were
     * linked carry the account's uid. Older entries only have a name, so they count for an
     * account only when that name belongs to exactly one schedulable account.
     */
    private function accountUid(ClinicRecord $entry, array $staffDirectory): ?string
    {
        if ($entry->staffId) {
            return collect($staffDirectory)->contains('uid', (string) $entry->staffId) ? (string) $entry->staffId : null;
        }

        $sameName = collect($staffDirectory)->where('name', (string) $entry->staff);

        return $sameName->count() === 1 ? $sameName->first()['uid'] : null;
    }

    private function availability(Collection $entries, bool $onLeave): string
    {
        if ($onLeave) {
            return 'On Leave';
        }

        if ($entries->isEmpty()) {
            return 'Unavailable';
        }

        $ranges = $entries->map(fn (array $entry) => $this->shifts->shiftRange($entry['shift']))->filter()->values();
        foreach ($ranges as $i => $first) {
            foreach ($ranges->slice($i + 1) as $second) {
                if ($this->shifts->overlaps($first, $second)) {
                    return 'Fully Booked';
                }
            }
        }

        return 'Available';
    }
}
