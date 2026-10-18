<?php

namespace App\Services\StaffSchedule;

use App\Services\Clinic\ClinicRecord;
use App\Services\Clinic\ClinicStore;
use App\Services\User\UserService;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/** Staff shifts and time off (Firestore `staffShifts` / `staffTimeOff`, see ClinicStore). */
class StaffScheduleService
{
    public function __construct(private ClinicStore $store, private ShiftConflictService $shifts, private UserService $users)
    {
    }

    public function overview(int $weekOffset): array
    {
        $weekOffset = max(-12, min(12, $weekOffset));
        $monday = CarbonImmutable::now()->startOfWeek()->addWeeks($weekOffset);
        $weekDays = collect(range(0, 6))->map(fn (int $i) => [
            'label' => $monday->addDays($i)->format('l'),
            'short' => $monday->addDays($i)->format('M j'),
        ])->all();

        $schedules = $this->store->all(ClinicStore::SHIFTS)->sortBy(fn (ClinicRecord $s) => (string) $s->shift)->values();
        $staffDirectory = $this->staffDirectory($schedules);

        $today = CarbonImmutable::today();
        $todayEntries = $schedules->where('day', $today->format('l'));
        $timeOffToday = $this->store->all(ClinicStore::TIME_OFF)
            ->where('date', $today->toDateString())
            ->map(fn (ClinicRecord $off) => $this->shifts->normalize($off->staff));

        $staffAvailability = [];
        $todayStaffList = [];
        foreach ($staffDirectory as $staff) {
            $name = $this->shifts->normalize($staff['name']);
            $entries = $todayEntries->filter(fn (ClinicRecord $entry) => $this->shifts->normalize($entry->staff) === $name);
            $status = $this->availability($entries, $timeOffToday->contains($name));
            $staffAvailability[$staff['name']] = $status;
            $todayStaffList[] = [
                'name' => $staff['name'],
                'role' => $staff['role'],
                'shift' => $entries->first()?->shift ?? 'Off',
                'room' => $entries->first()?->room ?? 'Not assigned',
                'status' => $status,
            ];
        }

        $weeklySchedule = [];
        foreach ($schedules as $entry) {
            $weeklySchedule[$entry->staff][$entry->day] ??= ['shift' => $entry->shift, 'room' => $entry->room];
        }

        return [
            'weekOffset' => $weekOffset,
            'staffDirectory' => $staffDirectory,
            'weekDays' => $weekDays,
            'staffAvailability' => $staffAvailability,
            'weeklySchedule' => $weeklySchedule,
            'todayStaffList' => $todayStaffList,
            'staffCount' => $todayEntries->pluck('staff')->unique()->count(),
            'todayShifts' => $todayEntries->count(),
            'activeRooms' => $todayEntries->pluck('room')->filter()->unique()->count(),
        ];
    }

    public function addShift(array $shift): string
    {
        return $this->store->create(ClinicStore::SHIFTS, [
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
            'staff' => $timeOff['staff'],
            'date' => CarbonImmutable::parse($timeOff['date'])->toDateString(),
            'type' => $timeOff['type'],
            'time' => $timeOff['time'],
            'reason' => $timeOff['reason'],
        ]);
    }

    /**
     * Active staff accounts from Firebase (every role except patients), plus anyone already on the schedule.
     */
    private function staffDirectory(Collection $schedules): array
    {
        $staff = collect($this->users->staff())
            ->filter(fn (array $user) => $user['active'])
            ->mapWithKeys(fn (array $user) => [$this->shifts->normalize($user['name']) => ['name' => $user['name'], 'role' => ucfirst($user['role'])]]);

        foreach ($schedules as $entry) {
            $key = $this->shifts->normalize($entry->staff);
            $staff->put($key, $staff->get($key) ?? ['name' => $entry->staff, 'role' => $entry->role]);
        }

        return $staff->values()->all();
    }

    private function availability(Collection $entries, bool $onLeave): string
    {
        if ($onLeave) {
            return 'On Leave';
        }

        if ($entries->isEmpty()) {
            return 'Unavailable';
        }

        $ranges = $entries->map(fn (ClinicRecord $entry) => $this->shifts->shiftRange((string) $entry->shift))->filter()->values();
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
