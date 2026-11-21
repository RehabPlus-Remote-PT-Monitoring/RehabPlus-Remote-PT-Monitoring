<?php

namespace App\Helpers;

use App\Services\Patient\ClearanceService;
use App\Services\Patient\ClinicalProfileService;
use App\Services\Patient\ExerciseCatalog;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** Form rules for the clinical & dietary profile and the physician sign-off. */
class ClinicalSafeguardValidation
{
    /**
     * Reassessment dates: up to a year back (so re-saving a profile whose
     * planned date has just passed isn't blocked) and five years ahead.
     */
    public static function reassessmentDates(): array
    {
        $today = CarbonImmutable::now(config('app.timezone'));

        return [
            'min' => $today->subYear()->toDateString(),
            'max' => $today->addYears(5)->toDateString(),
        ];
    }

    /** The final assessment happened today or earlier (never in the future), within five years. */
    public static function assessmentDates(): array
    {
        $today = CarbonImmutable::now(config('app.timezone'));

        return [
            'min' => $today->subYears(5)->toDateString(),
            'max' => $today->toDateString(),
        ];
    }

    public static function profile(Request $request): array
    {
        $dates = self::reassessmentDates();

        return $request->validate([
            'precautions' => 'nullable|string|max:'.ClinicalProfileService::MAX_PRECAUTIONS,
            'dietary_notes' => 'nullable|string|max:'.ClinicalProfileService::MAX_DIETARY_NOTES,
            'nutrition_flags' => 'nullable|array',
            'nutrition_flags.*' => ['string', Rule::in(array_keys(ClinicalProfileService::NUTRITION_FLAGS))],
            'restricted_exercises' => 'nullable|array',
            'restricted_exercises.*' => ['string', Rule::in(ExerciseCatalog::codes())],
            'low_tolerance' => 'nullable|boolean',
            'tolerance_note' => 'nullable|string|max:'.ClinicalProfileService::MAX_TOLERANCE_NOTE,
            'next_reassessment_at' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:'.$dates['min'], 'before_or_equal:'.$dates['max']],
        ]);
    }

    public static function clearance(Request $request): array
    {
        $dates = self::assessmentDates();

        return $request->validate([
            'decision' => ['required', Rule::in(array_keys(ClearanceService::DECISIONS))],
            'physician_name' => 'required|string|max:100',
            'physician_license' => 'required|string|max:40',
            'assessed_at' => ['required', 'date_format:Y-m-d', 'after_or_equal:'.$dates['min'], 'before_or_equal:'.$dates['max']],
            'findings' => 'required|string|max:2000',
            'recommendations' => 'nullable|string|max:1000',
            'attested' => 'accepted',
        ], [
            'attested.accepted' => 'Confirm that a physician performed a final assessment of this patient.',
            'assessed_at.before_or_equal' => 'The assessment date can\'t be in the future.',
        ]);
    }
}
