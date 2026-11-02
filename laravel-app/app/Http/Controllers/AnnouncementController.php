<?php

namespace App\Http\Controllers;

use App\Services\Announcement\AnnouncementService;
use App\Services\Firebase\FirestoreClient;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

/** Posting and removing clinic announcements. Administrators only; everyone sees them on the dashboard. */
class AnnouncementController extends Controller
{
    public function __construct(private AnnouncementService $announcements)
    {
    }

    public function index(Request $request): View
    {
        abort_unless($request->user()->isAdmin(), 403);

        return view('announcements.index', ['announcements' => $this->announcements->current()]);
    }

    public function store(Request $request): RedirectResponse
    {
        abort_unless($request->user()->isAdmin(), 403);

        $data = $request->validate([
            'title' => 'required|string|min:3|max:120',
            'body' => 'required|string|min:3|max:1000',
            'show_until' => 'nullable|date_format:Y-m-d|after_or_equal:today',
            'image' => ['nullable', 'file', 'mimetypes:image/jpeg,image/png,image/webp', 'max:2048'],
        ], [
            'show_until.after_or_equal' => 'Choose today or a later date.',
            'image.mimetypes' => 'Choose a JPG, PNG or WebP picture.',
            'image.max' => 'The picture must be 2 MB or smaller.',
        ]);

        if ($request->hasFile('image')) {
            $data['imageUrl'] = $this->announcements->imageDataUrl($request->file('image'));
        }
        unset($data['image']);

        $this->announcements->create($data, $request->user());

        return redirect()->route('announcements.index')->with('success', 'Announcement posted.');
    }

    public function destroy(Request $request, string $id): RedirectResponse
    {
        abort_unless($request->user()->isAdmin(), 403);
        abort_unless(FirestoreClient::isValidId($id), 404);

        $this->announcements->delete($id);

        return redirect()->route('announcements.index')->with('success', 'Announcement removed.');
    }
}
