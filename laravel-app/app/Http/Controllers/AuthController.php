<?php

namespace App\Http\Controllers;

use App\Auth\StaffUser;
use App\Services\Firebase\FirebaseAdmin;
use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreClient;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;

/**
 * Staff login with their Firebase Auth email and password. Only accounts whose
 * users/{uid}.role is admin, therapist or staff get in; patients use the app.
 */
class AuthController extends Controller
{
    public function __construct(private FirebaseAdmin $admin, private FirestoreClient $db)
    {
    }

    public function login(): View|RedirectResponse
    {
        if (Auth::check()) {
            return redirect()->route('dashboard');
        }

        return view('auth.login');
    }

    public function attempt(Request $request): RedirectResponse
    {
        $credentials = $request->validate([
            'email' => 'required|email',
            'password' => 'required|string',
        ]);

        try {
            $result = $this->admin->verifyPassword($credentials['email'], $credentials['password']);
            $doc = $result['uid'] ? $this->db->get("users/{$result['uid']}") : null;
        } catch (FirebaseException $e) {
            report($e);

            return $this->fail('Could not reach Firebase to check your login. Try again in a moment.');
        }

        if ($result['error'] === 'disabled') {
            return $this->fail('This account has been disabled. Ask an administrator to re-enable it.');
        }
        if ($result['error'] === 'throttled') {
            return $this->fail('Too many failed attempts. Wait a few minutes, then try again.');
        }
        if (! $result['uid']) {
            return $this->fail('Invalid email or password.');
        }
        if (($doc['role'] ?? null) === 'patient') {
            return $this->fail('Patient accounts sign in on the RehabPlus mobile app, not the clinic dashboard.');
        }

        $user = StaffUser::fromDocument($doc);
        if (! $user) {
            return $this->fail('This account does not have access to the clinic dashboard.');
        }

        Auth::login($user);
        $request->session()->regenerate();

        return redirect()->intended(route('dashboard'));
    }

    public function doLogout(Request $request): RedirectResponse
    {
        Auth::logout();

        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return redirect()->route('login.page');
    }

    private function fail(string $message): RedirectResponse
    {
        return back()->with('error', $message)->onlyInput('email');
    }
}
