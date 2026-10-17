<?php

namespace App\Helpers;

use App\Models\User;
use Illuminate\Http\Request;

class UserValidation
{
    /**
     * Roles that can be picked in the Create Account / Edit User form.
     * Patient accounts are created separately and can't be chosen here.
     */
    public const STAFF_ROLES = ['staff', 'therapist', 'superadmin'];

    public static function newAccount(Request $request): array
    {
        return $request->validate([
            'name' => 'required|min:2|max:100',
            'email' => 'required|email|unique:users,email',
            'password' => 'required|min:6',
        ]);
    }

    /**
     * Role for a new staff account (defaults to staff).
     */
    public static function staffRole(Request $request): string
    {
        return $request->validate([
            'role' => 'nullable|in:' . implode(',', self::STAFF_ROLES),
        ])['role'] ?? 'staff';
    }

    public static function update(Request $request, User $user): array
    {
        $rules = [
            'name' => 'required|min:2|max:100',
            'email' => 'required|email|unique:users,email,' . $user->id,
            'role' => 'nullable|in:' . implode(',', self::STAFF_ROLES),
        ];

        if ($request->filled('password')) {
            $rules['password'] = 'nullable|min:6';
        }

        return $request->validate($rules);
    }
}
