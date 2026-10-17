<?php

namespace App\Helpers;

use Illuminate\Http\Request;

class ExerciseValidation
{
    public static function record(Request $request): array
    {
        return $request->validate([
            'exercise_name' => 'required|max:150',
            'sets_prescribed' => 'required|integer|min:1',
            'sets_completed' => 'required|integer|min:0',
            'pain_level' => 'required|integer|min:0|max:10',
            'recorded_at' => 'required|date',
            'notes' => 'nullable|string',
        ]);
    }
}
