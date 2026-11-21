<?php

namespace App\Http\Controllers;

use App\Services\Dashboard\DailyInsightsService;
use App\Services\Dashboard\DashboardOverviewService;
use Illuminate\Http\Request;
use Illuminate\View\View;

/** The home dashboard. Reports & Analytics lives in ReportController. */
class DashboardController extends Controller
{
    public function __construct(private DashboardOverviewService $overview, private DailyInsightsService $daily)
    {
    }

    public function index(Request $request): View
    {
        $user = $request->user();
        $data = $this->overview->overview($user);

        return view('dashboard.index', $data + ['daily' => $this->daily->build($user, $data)]);
    }
}
