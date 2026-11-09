<?php

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * Staff logins use the clinic's domain or Gmail. Forgot-password codes go to
 * the login email, so it has to be an inbox the staff member can open, and
 * the clinic has no mailboxes on rehabplus.com yet. Patients keep
 * OfficialEmailDomain: they reset their password by text in the app.
 */
class StaffEmailDomain implements ValidationRule
{
    public const DOMAINS = ['rehabplus.com', 'gmail.com'];

    public const MESSAGE = 'Use an @rehabplus.com or @gmail.com email address for staff logins.';

    public static function allows(string $email): bool
    {
        $domains = implode('|', array_map(fn (string $domain) => preg_quote($domain, '/'), self::DOMAINS));

        return (bool) preg_match('/^[^@\s]+@('.$domains.')$/i', trim($email));
    }

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (! is_string($value) || ! self::allows($value)) {
            $fail(self::MESSAGE);
        }
    }
}
