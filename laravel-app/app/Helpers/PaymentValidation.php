<?php

namespace App\Helpers;

use Carbon\CarbonImmutable;
use Illuminate\Http\Request;

class PaymentValidation
{
    /** Payment dates: up to five years back, or a year ahead for a payment that's expected. */
    public static function dates(): array
    {
        return [
            'min' => CarbonImmutable::today()->subYears(5)->toDateString(),
            'max' => CarbonImmutable::today()->addYear()->toDateString(),
        ];
    }

    public static function payment(Request $request): array
    {
        $dates = self::dates();

        return $request->validate([
            'patient' => ['required', 'string', 'max:150'],
            'session' => ['required', 'string', 'max:150'],
            'fee' => ['required', 'numeric', 'min:0'],
            'discount' => ['nullable', 'numeric', 'min:0'],
            'tax_rate' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'status' => ['required', 'in:Paid,Pending,Partial'],
            'date' => ['required', 'date_format:Y-m-d', 'after_or_equal:'.$dates['min'], 'before_or_equal:'.$dates['max']],
        ]);
    }

    public static function status(Request $request): array
    {
        return $request->validate([
            'status' => ['required', 'in:Paid,Pending,Partial'],
        ]);
    }
}
