<?php

namespace App\Helpers;

use App\Rules\EmailNotTaken;
use App\Rules\OfficialEmailDomain;
use App\Services\Firebase\FirebaseAdmin;
use App\Services\Patient\PatientService;
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
            'dob' => 'nullable|date_format:Y-m-d|after_or_equal:1900-01-01|before_or_equal:today',
            'gender' => ['nullable', Rule::in(PatientService::GENDERS)],
            'weight_kg' => 'nullable|numeric|between:'.PatientService::MIN_WEIGHT_KG.','.PatientService::MAX_WEIGHT_KG,
            'height_cm' => 'nullable|numeric|between:'.PatientService::MIN_HEIGHT_CM.','.PatientService::MAX_HEIGHT_CM,
            'address_street' => 'nullable|string|max:150',
            'address_barangay' => 'nullable|string|max:100',
            'address_city' => 'nullable|string|max:100',
            'address_province' => 'nullable|string|max:100',
            'therapist_id' => 'nullable|string|max:128',
        ], [
            'dob.date_format' => 'Pick the date of birth from the calendar.',
            'dob.after_or_equal' => 'Pick a real date of birth from the calendar.',
            'dob.before_or_equal' => 'Date of birth can\'t be in the future.',
            'gender.in' => 'Pick a gender from the list.',
            'weight_kg.numeric' => 'Enter the weight as a number of kilograms.',
            'weight_kg.between' => 'Weight must be between '.PatientService::MIN_WEIGHT_KG.' and '.PatientService::MAX_WEIGHT_KG.' kg.',
            'height_cm.numeric' => 'Enter the height as a number of centimetres.',
            'height_cm.between' => 'Height must be between '.PatientService::MIN_HEIGHT_CM.' and '.PatientService::MAX_HEIGHT_CM.' cm.',
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
            'email' => ['required', 'email', 'max:150', new OfficialEmailDomain, new EmailNotTaken],
            'password' => ['required', 'string', 'min:'.FirebaseAdmin::MIN_PASSWORD, 'max:100', 'regex:/^[^\s-]+$/'],
        ], [
            'password.regex' => 'The temporary password cannot contain spaces or hyphens.',
        ]);
    }

}
