<?php

namespace App\Http\Controllers;

use App\Auth\StaffUser;
use App\Helpers\UserValidation;
use App\Services\User\UserService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

/**
 * Staff accounts (admin only): Firebase Auth logins with a role in Firestore
 * users/{uid}. Disabling stops sign-in for now. Archiving also takes the account
 * off the staff list; only an archived account can be deleted for good, and a
 * therapist with patients must be reassigned first. Leftover records with no
 * login can be deleted directly.
 */
class UserController extends Controller
{
    public function __construct(private UserService $users)
    {
    }

    public function index(Request $request): View
    {
        $all = $this->users->all();
        $showArchived = $request->boolean('archived');
        $staff = array_values(array_filter(
            $all,
            fn ($u) => in_array($u['role'], StaffUser::ROLES, true) && $u['archived'] === $showArchived,
        ));

        return view('admin.users', [
            'users' => $staff,
            'showArchived' => $showArchived,
            'archivedCount' => count(array_filter($all, fn ($u) => in_array($u['role'], StaffUser::ROLES, true) && $u['archived'])),
            'noLogin' => $this->users->withoutLogin($staff),
            'patientCount' => count(array_filter($all, fn ($u) => $u['role'] === 'patient')),
        ]);
    }

    public function create(): View
    {
        return view('users.form', ['user' => null]);
    }

    public function store(Request $request): RedirectResponse
    {
        $this->users->create(UserValidation::newAccount($request));

        return redirect()->route('users.index')->with('success', 'Account created. They can now sign in to the dashboard.');
    }

    public function edit(string $uid): View
    {
        return view('users.form', ['user' => $this->staffOr404($uid)]);
    }

    public function update(Request $request, string $uid): RedirectResponse
    {
        $user = $this->staffOr404($uid);
        $data = UserValidation::update($request, $user, $request->user());

        if ($this->users->removesLastAdmin($user, $data['role'])) {
            return back()->withInput()->with('error', 'At least one active administrator must remain. Make another administrator first.');
        }

        $this->users->update($user, $data);

        return redirect()->route('users.index')->with('success', 'User updated.');
    }

    /** Enable or disable a login. */
    public function status(Request $request, string $uid): RedirectResponse
    {
        $user = $this->staffOr404($uid);
        if ($user['uid'] === $request->user()->id) {
            return back()->with('error', 'You can\'t disable your own account.');
        }

        $active = $request->boolean('active');
        $this->users->setActive($user, $active);

        return back()->with('success', $active ? 'Account enabled.' : 'Account disabled. They can no longer sign in.');
    }

    /** Take the account off the staff list. Its login is disabled. */
    public function archive(Request $request, string $uid): RedirectResponse
    {
        $user = $this->staffOr404($uid);
        if ($user['uid'] === $request->user()->id) {
            return back()->with('error', 'You can\'t archive your own account.');
        }

        $this->users->setArchived($user, true, $request->user());

        return redirect()->route('users.index')->with('success', 'Account archived. They can no longer sign in. Restore it from Archived Staff, or delete it there for good.');
    }

    /** Put an archived account back on the staff list and let them sign in again. */
    public function restore(string $uid): RedirectResponse
    {
        $user = $this->staffOr404($uid);
        $this->users->setArchived($user, false);

        return redirect()->route('users.index')->with('success', 'Account restored. They can sign in again.');
    }

    /**
     * Delete the login and users/{uid} for good. Only archived accounts, and
     * leftover records with no login, can be deleted.
     */
    public function destroy(Request $request, string $uid): RedirectResponse
    {
        $user = $this->staffOr404($uid);
        if ($user['uid'] === $request->user()->id) {
            return back()->with('error', 'You can\'t delete your own account.');
        }

        $leftover = in_array($user['uid'], $this->users->withoutLogin([$user]), true);
        if (! $user['archived'] && ! $leftover) {
            return back()->with('error', 'Archive the account first, then delete it from Archived Staff.');
        }

        if ($reason = $this->users->delete($user)) {
            return back()->with('error', $reason);
        }

        $back = $user['archived'] ? route('users.index', ['archived' => 1]) : route('users.index');

        return redirect($back)->with('success', 'Account deleted permanently.');
    }

    private function staffOr404(string $uid): array
    {
        $user = $this->users->findStaff($uid);
        abort_unless($user, 404);

        return $user;
    }
}
