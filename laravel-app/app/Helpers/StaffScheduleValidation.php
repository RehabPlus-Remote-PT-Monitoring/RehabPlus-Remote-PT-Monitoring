<?php

namespace App\Helpers;

use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class StaffScheduleValidation
{
    public const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    /** The staff account is picked by uid; its name and role come from the account, not from the form. */
    public static function shift(Request $request): array
    {
        $validated = $request->validate([
            'staff_id' => ['required', 'string', 'max:128'],
            'day' => ['required', 'in:' . implode(',', self::DAYS)],
            'shift' => ['required', Rule::in(config('clinic.shifts'))],
            'room' => ['required', Rule::in(config('clinic.rooms'))],
        ]);

        return $validated;
    }

    /** The earliest and latest dates time off can be recorded for: a year either way from today. */
    public static function timeOffDates(): array
    {
        return [
            'min' => CarbonImmutable::today()->subYear()->toDateString(),
            'max' => CarbonImmutable::today()->addYear()->toDateString(),
        ];
    }

    public static function timeOff(Request $request): array
    {
        $dates = self::timeOffDates();

        $validated = $request->validate([
            'staff_id' => ['required', 'string', 'max:128'],
            'date' => ['required', 'date_format:Y-m-d', 'after_or_equal:'.$dates['min'], 'before_or_equal:'.$dates['max']],
            'time_off_type' => ['nullable', 'in:Full day,Specific time'],
            'time' => ['required_if:time_off_type,Specific time', 'nullable', Rule::in(config('clinic.shifts'))],
            'reason' => ['required', 'string', 'max:255'],
        ]);

        $type = $validated['time_off_type'] ?? 'Full day';

        return [
            'staff_id' => $validated['staff_id'],
            'date' => $validated['date'],
            'type' => $type,
            'time' => $type === 'Specific time' ? $validated['time'] : 'Full day',
            'reason' => $validated['reason'],
        ];
    }
}
