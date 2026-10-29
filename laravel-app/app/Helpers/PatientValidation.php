<?php

namespace App\Helpers;

use App\Rules\OfficialEmailDomain;
use App\Services\Firebase\FirebaseAdmin;
use Illuminate\Http\Request;

class PatientValidation
{
    /** Profile fields shared by create and edit (limits match the app/rules). */
    public static function profile(Request $request): array
    {
        return $request->validate([
            'name' => 'required|string|min:2|max:100',
            'condition' => 'required|string|min:2|max:150',
            'medical_summary' => 'nullable|string|max:2000',
            'therapy_plan' => 'nullable|string|max:2000',
            'phone' => 'nullable|digits_between:1,30',
            'dob' => 'nullable|date_format:Y-m-d|before_or_equal:today',
            'therapist_id' => 'nullable|string|max:128',
        ], [
            'phone.digits_between' => 'Phone number can only contain numbers.',
            'dob.date_format' => 'Pick the date of birth from the calendar.',
            'dob.before_or_equal' => 'Date of birth can\'t be in the future.',
        ]);
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
