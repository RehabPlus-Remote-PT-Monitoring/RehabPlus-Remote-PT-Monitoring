<?php

namespace App\Helpers;

use App\Services\Patient\ClinicalRecordService;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class ClinicalValidation
{
    /** Assessments are recorded for today or up to five years back. */
    public static function assessmentDates(): array
    {
        return [
            'min' => CarbonImmutable::today()->subYears(5)->toDateString(),
            'max' => CarbonImmutable::today()->toDateString(),
        ];
    }

    /** Goal targets are from today to five years ahead. */
    public static function goalDates(): array
    {
        return [
            'min' => CarbonImmutable::today()->toDateString(),
            'max' => CarbonImmutable::today()->addYears(5)->toDateString(),
        ];
    }

    /** Progress in steps of 5%, plus the goal's saved value if it's between steps. */
    public static function progressChoices(?int $current = null): array
    {
        return collect(range(0, 100, 5))
            ->when($current !== null, fn ($choices) => $choices->push($current))
            ->unique()
            ->sort()
            ->values()
            ->all();
    }

    public static function assessment(Request $request): array
    {
        $dates = self::assessmentDates();

        return $request->validate([
            'patient_uid' => 'required|string|max:128',
            'type' => 'required|string|max:60',
            'score' => 'required|integer|min:0|max:100',
            'date' => ['required', 'date_format:Y-m-d', 'after_or_equal:'.$dates['min'], 'before_or_equal:'.$dates['max']],
            'notes' => 'nullable|string|max:1000',
        ]);
    }

    public static function goal(Request $request): array
    {
        $dates = self::goalDates();

        return $request->validate([
            'patient_uid' => 'required|string|max:128',
            'title' => 'required|string|max:150',
            'details' => 'nullable|string|max:1000',
            'target_date' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:'.$dates['min'], 'before_or_equal:'.$dates['max']],
            'progress' => 'nullable|integer|min:0|max:100',
        ]);
    }

    public static function goalUpdate(Request $request): array
    {
        return $request->validate([
            'status' => ['required', Rule::in(array_keys(ClinicalRecordService::GOAL_STATUSES))],
            'progress' => 'required|integer|min:0|max:100',
        ]);
    }

    public static function note(Request $request): array
    {
        return $request->validate([
            'patient_uid' => 'required|string|max:128',
            'topic' => 'required|string|max:100',
            'text' => 'required|string|max:2000',
            'date' => 'required|date|before_or_equal:today',
        ]);
    }
}
