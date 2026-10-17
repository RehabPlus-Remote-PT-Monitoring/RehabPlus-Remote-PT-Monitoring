<?php

namespace App\Helpers;

use Illuminate\Http\Request;

class PatientValidation
{
    public static function patient(Request $request): array
    {
        return $request->validate([
            'name' => 'required|min:2|max:100',
            'condition' => 'required|min:2|max:150',
            'medical_summary' => 'nullable|max:1000',
            'therapy_plan' => 'nullable|max:1000',
            'avatar' => 'nullable|image|max:2048',
        ]);
    }
}
