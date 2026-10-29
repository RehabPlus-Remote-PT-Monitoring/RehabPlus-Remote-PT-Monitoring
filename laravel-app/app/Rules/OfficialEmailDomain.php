<?php

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * Staff and patient logins must use the clinic's own domain. Checked before
 * anything is written to Firebase Auth or Firestore.
 */
class OfficialEmailDomain implements ValidationRule
{
    public const MESSAGE = 'Invalid email domain. Account creation is strictly restricted to official @rehabplus.com email addresses.';

    public static function allows(string $email): bool
    {
        return (bool) preg_match('/^[^@\s]+@rehabplus\.com$/i', trim($email));
    }

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (! is_string($value) || ! self::allows($value)) {
            $fail(self::MESSAGE);
        }
    }
}
