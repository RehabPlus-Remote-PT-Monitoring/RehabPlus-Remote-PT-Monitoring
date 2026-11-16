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
            'stories' => $this->stories(),
        ]);
    }

    /**
     * The "Today at Rehab+" pictures: the posts marked as stories first (newest first), then the featured
     * pictures from config/clinic.php.
     *
     * @return array<int, array{title: string, caption: string, image: string}>
     */
    private function stories(): array
    {
        $posted = array_map(fn (array $story) => [
            'title' => $story['title'],
            'caption' => $story['body'],
            'image' => $story['imageUrl'],
        ], $this->announcements->stories());

        $featured = array_map(fn (array $story) => [
            'title' => $story['title'],
            'caption' => $story['caption'],
            'image' => asset($story['image']),
        ], config('clinic.featured_stories', []));

        return array_values(array_merge($posted, $featured));
    }
}
