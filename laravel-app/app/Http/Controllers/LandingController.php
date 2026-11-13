<?php

namespace App\Http\Controllers;

use App\Services\Announcement\AnnouncementService;
use App\Services\User\StaffDirectory;
use Illuminate\View\View;

/**
 * The public welcome page at the site root. Shows the same clinic details and
 * team as the Home page inside the dashboard, without any private information.
 */
class LandingController extends Controller
{
    public function __construct(private StaffDirectory $directory, private AnnouncementService $announcements)
    {
    }

    public function index(): View
    {
        return view('landing', [
            'clinic' => config('clinic'),
            'staff' => $this->directory->board(),
            'announcements' => $this->announcements->current(),
        ]);
    }
}
