<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;

class AuthController extends Controller
{
    public function login(): View|
    \Illuminate\Http\RedirectResponse
    {
        if (Auth::check()) {
            return $this->redirectAuthenticatedUser();
        }

        Auth::logout();

        return view('auth.login');
    }

    protected function redirectAuthenticatedUser()
    {
        $user = Auth::user();

        if ($user && $user->role === 'patient') {
            return redirect()->route('patient.portal');
        }

        return redirect()->route('dashboard');
    }

    public function attempt(Request $request)
    {
        $email = trim((string) $request->input('email'));
        $password = (string) $request->input('password');
        $user = User::where('email', $email)->first();

        if ($user && $user->role === 'patient') {
            return back()->with('error', 'Patient accounts cannot use the admin login. Use the patient portal login.')->withInput();
        }

        if ($user && (int) $user->is_active === 1 && password_verify($password, $user->password)) {
            Auth::login($user);
            $request->session()->regenerate();

            return redirect()->intended('/dashboard');
        }

        return back()->with('error', 'Invalid email or password.')->withInput();
    }

    public function doLogout(Request $request)
    {
        Auth::logout();

        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return redirect()->route('login.page');
    }
}
