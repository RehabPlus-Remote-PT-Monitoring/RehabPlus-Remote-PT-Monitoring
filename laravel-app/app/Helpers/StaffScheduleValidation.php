<?php

namespace App\Helpers;

use Illuminate\Http\Request;

class StaffScheduleValidation
{
    public const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    /** The staff account is picked by uid; its name and role come from the account, not from the form. */
    public static function shift(Request $request): array
    {
        $validated = $request->validate([
            'staff_id' => ['required', 'string', 'max:128'],
            'day' => ['required', 'in:' . implode(',', self::DAYS)],
            'shift' => ['required', 'string', 'max:50'],
            'room' => ['nullable', 'string', 'max:100'],
        ]);
        $validated['room'] = trim((string) ($validated['room'] ?? '')) ?: 'General Room';

        return $validated;
    }

    public static function timeOff(Request $request): array
    {
        $validated = $request->validate([
            'staff_id' => ['required', 'string', 'max:128'],
            'date' => ['required', 'date'],
            'time_off_type' => ['nullable', 'in:Full day,Specific time'],
            'time' => ['nullable', 'string', 'max:50'],
            'reason' => ['required', 'string', 'max:255'],
        ]);

        return [
            'staff_id' => $validated['staff_id'],
            'date' => $validated['date'],
            'type' => $validated['time_off_type'] ?? 'Full day',
            'time' => trim((string) ($validated['time'] ?? '')) ?: 'Full day',
            'reason' => $validated['reason'],
        ];
    }
}
