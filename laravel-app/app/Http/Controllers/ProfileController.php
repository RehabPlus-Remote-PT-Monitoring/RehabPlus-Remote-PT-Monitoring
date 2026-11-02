<?php

namespace App\Http\Controllers;

use App\Helpers\UserValidation;
use App\Services\User\UserService;
use Illuminate\Http\Request;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\UploadedFile;
use Illuminate\View\View;

/**
 * Staff edit their own name and profile picture. The role is not editable here:
 * administrators change roles on Staff Accounts.
 */
class ProfileController extends Controller
{
    private const PHOTO_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

    /** Firestore documents are capped at 1 MiB and base64 adds a third, so pictures stay small. */
    private const PHOTO_MAX_KB = 500;

    public function __construct(private UserService $users)
    {
    }

    public function edit(Request $request): View
    {
        return view('profile.edit', ['user' => $this->current($request)]);
    }

    public function update(Request $request): RedirectResponse
    {
        $current = $this->current($request);

        $data = $request->validate([
            'name' => 'required|string|min:2|max:100',
            'photo' => ['nullable', 'file', 'mimetypes:'.implode(',', self::PHOTO_TYPES), 'max:'.self::PHOTO_MAX_KB],
            'remove_photo' => 'nullable|boolean',
        ], [
            'photo.mimetypes' => 'Choose a JPG, PNG or WebP picture.',
            'photo.max' => 'The picture must be 500 KB or smaller.',
        ]);

        $change = ['name' => $data['name'], 'role' => $current['role']] + UserValidation::contact($request);
        if ($request->boolean('remove_photo')) {
            $change['photoUrl'] = '';
        } elseif ($request->hasFile('photo')) {
            $change['photoUrl'] = $this->dataUrl($request->file('photo'));
        }

        $this->users->update($current, $change);

        return redirect()->route('profile.edit')->with('success', 'Profile saved.');
    }

    /** The signed-in staff member, read fresh from Firestore. */
    private function current(Request $request): array
    {
        return $this->users->findStaff($request->user()->id) ?? abort(404);
    }

    /** The picture as a data URL, so it lives in the user's document and works on any host. */
    private function dataUrl(UploadedFile $file): string
    {
        return 'data:'.$file->getMimeType().';base64,'.base64_encode($file->get());
    }
}
