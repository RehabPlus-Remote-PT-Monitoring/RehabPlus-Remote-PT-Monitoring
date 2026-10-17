<?php

namespace App\Services\User;

use App\Models\Patient;
use App\Models\User;
use Illuminate\Http\Request;

class UserService
{
    public function createAccount(array $data, string $role): User
    {
        $data['role'] = $role;
        $data['is_active'] = true;
        $data['password'] = bcrypt($data['password']);

        return User::create($data);
    }

    public function createPatientAccount(array $data): User
    {
        $user = $this->createAccount($data, 'patient');

        Patient::create([
            'user_id' => $user->id,
            'name' => $data['name'],
            'condition' => 'Not specified',
        ]);

        return $user;
    }

    public function update(User $user, array $data, Request $request): void
    {
        // Therapist and patient roles are locked; other accounts may change role.
        if ($user->role === 'therapist' || $user->role === 'patient') {
            $data['role'] = $user->role;
        } else {
            $data['role'] = $request->input('role', $user->role);
        }

        if ($request->filled('password')) {
            $data['password'] = bcrypt($request->input('password'));
        }

        $user->update($data);
    }
}
