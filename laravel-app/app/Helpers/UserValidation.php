<?php

namespace App\Helpers;

use App\Auth\StaffUser;
use App\Helpers\PhoneNumber;
use App\Rules\EmailNotTaken;
use App\Rules\OfficialEmailDomain;
use App\Services\Firebase\FirebaseAdmin;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class UserValidation
{
    /**
     * Roles that can be picked in the Create Account / Edit User form.
     * Patient accounts are created from the Patients page and can't be chosen here.
     */
    public const STAFF_ROLES = StaffUser::ROLES;

    public static function newAccount(Request $request): array
    {
        $data = $request->validate([
            'name' => 'required|string|min:2|max:100',
            'email' => ['required', 'email', 'max:150', new OfficialEmailDomain, new EmailNotTaken],
            'password' => 'required|string|min:'.FirebaseAdmin::MIN_PASSWORD.'|max:100',
            'role' => ['nullable', Rule::in(self::STAFF_ROLES)],
        ]);
        $data['role'] ??= StaffUser::THERAPIST;

        return $data + self::contact($request);
    }

    /**
     * The personal contact number and email shown on the website's team section.
     * They are optional and separate from the @rehabplus.com login email. A blank
     * field leaves no contact detail on the account.
     *
     * @return array{contactPhone: string, contactEmail: string}
     */
    public static function contact(Request $request): array
    {
        $data = $request->validate([
            'phone_country' => ['nullable', Rule::in(PhoneNumber::isoCodes())],
            'phone' => ['nullable', 'string', 'max:20'],
            'contact_email' => ['nullable', 'email', 'max:150', function (string $attribute, mixed $value, Closure $fail) {
                if (is_string($value) && OfficialEmailDomain::allows($value)) {
                    $fail('Use the personal email, such as Gmail. The @rehabplus.com address is for logging in.');
                }
            }],
        ]);

        // The number is checked against the chosen country and saved in the +country format.
        $national = trim((string) ($data['phone'] ?? ''));
        $iso = $data['phone_country'] ?? PhoneNumber::DEFAULT_COUNTRY;
        if ($national !== '' && ($problem = PhoneNumber::problem($iso, $national)) !== null) {
            throw ValidationException::withMessages(['phone' => $problem]);
        }

        return [
            'contactPhone' => $national === '' ? '' : PhoneNumber::toStored($iso, $national),
            'contactEmail' => strtolower(trim((string) ($data['contact_email'] ?? ''))),
        ];
    }

    /**
     * Name, role and optional new password. Therapist accounts keep their role
     * (their patients are linked to them), and admins can't change their own
     * role, so the clinic can't lose its last admin by accident.
     */
    public static function update(Request $request, array $user, StaffUser $by): array
    {
        $data = $request->validate([
            'name' => 'required|string|min:2|max:100',
            'role' => ['nullable', Rule::in(self::STAFF_ROLES)],
            'password' => 'nullable|string|min:'.FirebaseAdmin::MIN_PASSWORD.'|max:100',
        ]);

        if ($user['role'] === StaffUser::THERAPIST || $user['uid'] === $by->id || empty($data['role'])) {
            $data['role'] = $user['role'];
        }
        if (empty($data['password'])) {
            unset($data['password']);
        }

        return $data + self::contact($request);
    }
}
