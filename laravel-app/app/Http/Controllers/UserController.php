<?php

namespace App\Http\Controllers;

use App\Helpers\UserValidation;
use App\Models\User;
use App\Services\User\UserService;
use Illuminate\Http\Request;
use Illuminate\View\View;

class UserController extends Controller
{
    public function __construct(private UserService $users)
    {
    }

    public function index(): View
    {
        return view('users.index', ['users' => User::all()]);
    }

    public function create(): View
    {
        return view('users.form', ['user' => null, 'errors' => []]);
    }

    public function store(Request $request)
    {
        $role = UserValidation::staffRole($request);

        $this->users->createAccount(UserValidation::newAccount($request), $role);

        return redirect()->route('users.index')->with('success', 'Account created successfully.');
    }

    public function createPatient(Request $request)
    {
        $this->users->createPatientAccount(UserValidation::newAccount($request));

        return redirect()->route('users.index')->with('success', 'Patient account created successfully.');
    }

    public function edit(int $id)
    {
        return view('users.form', ['user' => User::findOrFail($id), 'errors' => []]);
    }

    public function show(int $id)
    {
        return view('users.show', ['user' => User::findOrFail($id)]);
    }

    public function update(Request $request, int $id)
    {
        $user = User::findOrFail($id);

        $this->users->update($user, UserValidation::update($request, $user), $request);

        return redirect()->route('users.index')->with('success', 'User updated successfully.');
    }

    public function delete(int $id)
    {
        User::findOrFail($id)->delete();

        return redirect()->route('users.index')->with('success', 'User deleted.');
    }
}
