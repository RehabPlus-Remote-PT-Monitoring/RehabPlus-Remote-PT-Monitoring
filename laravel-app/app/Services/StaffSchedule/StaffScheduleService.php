<?php

namespace App\Services\StaffSchedule;

use App\Models\StaffSchedule;
use App\Models\StaffTimeOff;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

class StaffScheduleService
{
    public function __construct(private ShiftConflictService $shifts)
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

        $schedules = StaffSchedule::orderBy('shift')->get();
        $staffDirectory = $this->staffDirectory($schedules);

        $today = CarbonImmutable::today();
        $todayEntries = $schedules->where('day', $today->format('l'));
        $timeOffToday = StaffTimeOff::whereDate('date', $today)->pluck('staff')->map(fn ($name) => $this->shifts->normalize($name));

        $staffAvailability = [];
        $todayStaffList = [];
        foreach ($staffDirectory as $staff) {
            $name = $this->shifts->normalize($staff['name']);
            $entries = $todayEntries->filter(fn (StaffSchedule $entry) => $this->shifts->normalize($entry->staff) === $name);
            $status = $this->availability($entries, $timeOffToday->contains($name));
            $staffAvailability[$staff['name']] = $status;
            $todayStaffList[] = [
                'name' => $staff['name'],
                'role' => $staff['role'],
                'shift' => $entries->first()->shift ?? 'Off',
                'room' => $entries->first()->room ?? 'Not assigned',
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

    /**
     * Staff accounts from users (every role except patients), plus anyone already on the schedule.
     */
    private function staffDirectory(Collection $schedules): array
    {
        $staff = User::where('role', '!=', 'patient')
            ->orderBy('name')
            ->get()
            ->mapWithKeys(fn (User $user) => [$this->shifts->normalize($user->name) => ['name' => $user->name, 'role' => ucfirst($user->role)]]);

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

        $ranges = $entries->map(fn (StaffSchedule $entry) => $this->shifts->shiftRange($entry->shift))->filter()->values();
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
