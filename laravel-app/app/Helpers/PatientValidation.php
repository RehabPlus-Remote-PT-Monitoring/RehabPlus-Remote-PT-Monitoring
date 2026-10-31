<?php

namespace App\Helpers;

use App\Rules\OfficialEmailDomain;
use App\Services\Firebase\FirebaseAdmin;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class PatientValidation
{
    /** Profile fields shared by create and edit (limits match the app/rules). */
    public static function profile(Request $request): array
    {
        $data = $request->validate([
            'name' => 'required|string|min:2|max:100',
            'condition' => 'required|string|min:2|max:150',
            'medical_summary' => 'nullable|string|max:2000',
            'therapy_plan' => 'nullable|string|max:2000',
            'phone_country' => ['nullable', Rule::in(PhoneNumber::isoCodes())],
            'phone' => 'nullable|string|max:20',
            'dob' => 'nullable|date_format:Y-m-d|before_or_equal:today',
            'therapist_id' => 'nullable|string|max:128',
        ], [
            'dob.date_format' => 'Pick the date of birth from the calendar.',
            'dob.before_or_equal' => 'Date of birth can\'t be in the future.',
        ]);

        // The number is checked against the chosen country and saved in the +country format.
        $national = trim((string) ($data['phone'] ?? ''));
        $iso = $data['phone_country'] ?? PhoneNumber::DEFAULT_COUNTRY;
        if ($national !== '' && ($problem = PhoneNumber::problem($iso, $national)) !== null) {
            throw ValidationException::withMessages(['phone' => $problem]);
        }
        $data['phone'] = $national === '' ? '' : PhoneNumber::toStored($iso, $national);
        unset($data['phone_country']);

        return $data;
    }

    /** New patient: profile plus the app login (email + temporary password). */
    public static function create(Request $request): array
    {
        return self::profile($request) + $request->validate([
            'email' => ['required', 'email', 'max:150', new OfficialEmailDomain],
            'password' => 'required|string|min:'.FirebaseAdmin::MIN_PASSWORD.'|max:100|confirmed',
        ]);
    }

    public static function password(Request $request): array
    {
        return $request->validate([
            'password' => 'required|string|min:'.FirebaseAdmin::MIN_PASSWORD.'|max:100|confirmed',
        ]);
    }
}
