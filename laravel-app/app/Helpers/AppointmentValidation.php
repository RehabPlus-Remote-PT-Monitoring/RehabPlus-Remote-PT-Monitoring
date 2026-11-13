<?php

namespace App\Helpers;

use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AppointmentValidation
{
    public const STATUSES = ['Upcoming', 'Completed', 'Cancelled'];

    /** Appointment dates: up to five years back and two years ahead. */
    public static function dates(): array
    {
        return [
            'min' => CarbonImmutable::today()->subYears(5)->toDateString(),
            'max' => CarbonImmutable::today()->addYears(2)->toDateString(),
        ];
    }

    /** Session types offered in the picker: the clinic's classes plus the one-to-one physical therapy session. */
    public static function sessionOptions(): array
    {
        return collect(['Physical Therapy'])
            ->merge(collect(config('clinic.classes', []))->pluck('title'))
            ->unique()
            ->values()
            ->all();
    }

    /** Times and their picker options: every half hour from 8:00 AM to 6:00 PM. */
    public static function timeOptions(): array
    {
        return collect(range(8 * 60, 18 * 60, 30))
            ->map(fn (int $minutes) => CarbonImmutable::createFromTime(intdiv($minutes, 60), $minutes % 60)->format('g:i A'))
            ->all();
    }

    /** A time typed or picked as 9:30 AM, 9:30am or 09:30. Anything else is refused. */
    public static function normalizeTime(string $time): string
    {
        $clean = strtoupper(trim(preg_replace('/\s+/', ' ', preg_replace('/(?<=\d)(?=[AP]M$)/i', ' ', trim($time)))));

        if (! preg_match('/^(\d{1,2}):([0-5]\d) ?(AM|PM)?$/', $clean, $match)) {
            throw ValidationException::withMessages(['time' => 'Enter a time such as 9:30 AM.']);
        }

        [, $hour, $minute, $meridiem] = array_pad($match, 4, '');
        $hour = (int) $hour;
        $valid = $meridiem !== '' ? $hour >= 1 && $hour <= 12 : $hour <= 23;
        if (! $valid) {
            throw ValidationException::withMessages(['time' => 'Enter a time such as 9:30 AM.']);
        }

        $hour24 = $meridiem === '' ? $hour : ($hour % 12) + ($meridiem === 'PM' ? 12 : 0);

        return CarbonImmutable::createFromTime($hour24, (int) $minute)->format('g:i A');
    }

    public static function appointment(Request $request): array
    {
        $dates = self::dates();

        $data = $request->validate([
            'patient' => 'required|min:2|max:100',
            'therapist_id' => 'required|string|max:128',
            'patient_condition' => 'required|min:2|max:150',
            'contact_country' => ['nullable', Rule::in(PhoneNumber::isoCodes())],
            'contact' => 'required|string|max:20',
            'date' => ['required', 'date_format:Y-m-d', 'after_or_equal:'.$dates['min'], 'before_or_equal:'.$dates['max']],
            'time' => ['required', 'string', 'max:20'],
            'session' => 'required|max:100',
            'notes' => 'nullable|string',
            'status' => 'nullable|string',
        ]);

        // The time is saved the way the clinic reads it, such as 9:30 AM, whether typed or picked.
        $data['time'] = self::normalizeTime($data['time']);

        // The contact number is checked against the chosen country and saved in the +country format.
        $iso = $data['contact_country'] ?? PhoneNumber::DEFAULT_COUNTRY;
        $national = trim($data['contact']);
        if (($problem = PhoneNumber::problem($iso, $national)) !== null) {
            throw ValidationException::withMessages(['contact' => $problem]);
        }
        $data['contact'] = PhoneNumber::toStored($iso, $national);
        unset($data['contact_country']);

        return $data;
    }

    public static function isValidStatus(mixed $status): bool
    {
        return in_array($status, self::STATUSES, true);
    }
}
