<?php

namespace App\Rules;

use App\Services\User\EmailAvailability;
use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/** Refuses an email that another staff or patient account already uses. */
class EmailNotTaken implements ValidationRule
{
    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (is_string($value) && app(EmailAvailability::class)->isTaken($value)) {
            $fail(EmailAvailability::TAKEN_MESSAGE);
        }
    }
}
