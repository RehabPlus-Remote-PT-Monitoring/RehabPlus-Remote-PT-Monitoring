<?php

namespace App\Helpers;

use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AppointmentValidation
{
    public const STATUSES = ['Upcoming', 'Completed', 'Cancelled'];

    public static function appointment(Request $request): array
    {
        $data = $request->validate([
            'patient' => 'required|min:2|max:100',
            'therapist' => 'required|min:2|max:100',
            'patient_condition' => 'required|min:2|max:150',
            'contact_country' => ['nullable', Rule::in(PhoneNumber::isoCodes())],
            'contact' => 'required|string|max:20',
            'date' => 'required|date',
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
