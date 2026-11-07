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
            'time' => 'required',
            'session' => 'required|max:100',
            'notes' => 'nullable|string',
            'status' => 'nullable|string',
        ]);

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
