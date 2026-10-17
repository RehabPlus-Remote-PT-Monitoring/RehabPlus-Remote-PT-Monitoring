<?php

namespace App\Http\Controllers;

use App\Services\Dashboard\DashboardOverviewService;
use App\Services\Dashboard\PatientStatisticsService;
use Illuminate\Http\Request;
use Illuminate\View\View;

class DashboardController extends Controller
{
    public function __construct(
        private DashboardOverviewService $overview,
        private PatientStatisticsService $statistics,
    ) {
    }

    public function index(): View
    {
        return view('dashboard.index', $this->overview->overview());
    }

    public function analytics(): View
    {
        return view('dashboard.analytics', $this->overview->overview());
    }

    public function patientStatistics(Request $request): View
    {
        return view('dashboard.patient_statistics', $this->statistics->patientStatistics($request));
    }

    public function exportPatientStatisticsCsv(Request $request)
    {
        $rows = $this->statistics->patientStatisticsCsvRows($request);
        $filename = 'patient-statistics-' . now()->format('YmdHis') . '.csv';

        return response()->stream(function () use ($rows) {
            $handle = fopen('php://output', 'w');
            foreach ($rows as $row) {
                fputcsv($handle, $row);
            }
            fclose($handle);
        }, 200, [
            'Content-Type' => 'text/csv',
            'Content-Disposition' => 'attachment; filename="' . $filename . '"',
        ]);
    }

    public function exportPatientStatisticsPdf(Request $request): View
    {
        return view('dashboard.patient_statistics_pdf', $this->statistics->patientStatisticsPdf($request));
    }
}
