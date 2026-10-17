<?php

namespace App\Services\Dashboard;

use App\Models\Patient;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PatientStatisticsService
{
    public function patientStatistics(Request $request): array
    {
        $filters = $this->resolveFilters($request);
        $range = $this->resolveDateRange($request);

        $selectedPatients = $this->buildPatientQuery($filters, $range['start'], $range['end'])->get();

        $summary = [
            'totalPatients' => $selectedPatients->count(),
            'activePatients' => $selectedPatients->where('patient_is_active', 1)->count(),
            'inactivePatients' => $selectedPatients->where('patient_is_active', 0)->count(),
            'newPatientsThisMonth' => $this->newPatientsThisMonth($filters),
        ];

        $recentPatients = $this->buildPatientQuery($filters, $range['start'], $range['end'])
            ->orderBy('patients.created_at', 'desc')
            ->paginate(10)
            ->appends($request->query());

        return [
            'filters' => $filters,
            'rangeLabel' => $range['label'],
            'summary' => $summary,
            'registrationTrend' => $this->buildRegistrationTrend($filters, $range['start'], $range['end']),
            'conditionChart' => $this->buildConditionChart($selectedPatients),
            'growthSummary' => $this->buildGrowthComparison($filters, $range),
            'recentPatients' => $recentPatients,
            'conditionOptions' => $this->distinctPatientValues('condition'),
            'therapistOptions' => $this->distinctPatientValues('assigned_to'),
        ];
    }

    /**
     * Rows for the patient statistics CSV export.
     */
    public function patientStatisticsCsvRows(Request $request): array
    {
        $filters = $this->resolveFilters($request);
        $range = $this->resolveDateRange($request);
        $selectedPatients = $this->buildPatientQuery($filters, $range['start'], $range['end'])
            ->orderBy('patients.created_at', 'desc')
            ->get();

        $rows = [
            ['RehabPlus', 'Patient Statistics'],
            ['Selected range', $range['label']],
            ['Generated', now()->format('F j, Y H:i:s')],
            [],
            ['Total Patients', $selectedPatients->count()],
            ['Active Patients', $selectedPatients->where('patient_is_active', 1)->count()],
            ['Inactive Patients', $selectedPatients->where('patient_is_active', 0)->count()],
            ['New Patients This Month', $this->newPatientsThisMonth($filters)],
            [],
            ['Patient Name', 'Condition', 'Assigned Therapist', 'Registration Date', 'Status'],
        ];

        foreach ($selectedPatients as $patient) {
            $rows[] = [
                $patient->name,
                $patient->condition ?: 'Unspecified',
                $patient->assigned_to ?: 'Unassigned',
                $patient->created_at ? $patient->created_at->format('Y-m-d H:i:s') : '',
                $patient->patient_is_active ? 'Active' : 'Inactive',
            ];
        }

        return $rows;
    }

    public function patientStatisticsPdf(Request $request): array
    {
        $filters = $this->resolveFilters($request);
        $range = $this->resolveDateRange($request);
        $selectedPatients = $this->buildPatientQuery($filters, $range['start'], $range['end'])
            ->orderBy('patients.created_at', 'desc')
            ->paginate(20);

        return [
            'summary' => [
                'totalPatients' => $selectedPatients->total(),
                'activePatients' => $this->buildPatientQuery($filters, $range['start'], $range['end'])->where('users.is_active', true)->count(),
                'inactivePatients' => $this->buildPatientQuery($filters, $range['start'], $range['end'])->where('users.is_active', false)->count(),
                'newPatientsThisMonth' => $this->newPatientsThisMonth($filters),
            ],
            'rangeLabel' => $range['label'],
            'recentPatients' => $selectedPatients,
        ];
    }

    protected function newPatientsThisMonth(array $filters): int
    {
        return $this->buildPatientQuery($filters, Carbon::now()->startOfMonth(), Carbon::now()->endOfMonth())->count();
    }

    protected function distinctPatientValues(string $column): array
    {
        return Patient::query()
            ->select($column)
            ->whereNotNull($column)
            ->where($column, '!=', '')
            ->distinct()
            ->orderBy($column)
            ->pluck($column)
            ->toArray();
    }

    protected function resolveFilters(Request $request): array
    {
        return [
            'range' => $request->query('range', 'last_12_months'),
            'condition' => trim((string) $request->query('condition', '')),
            'therapist' => trim((string) $request->query('therapist', '')),
            'status' => trim((string) $request->query('status', '')),
            'from' => $request->query('from'),
            'to' => $request->query('to'),
        ];
    }

    protected function resolveDateRange(Request $request): array
    {
        $preset = $request->query('range', 'last_12_months');
        $from = $request->query('from');
        $to = $request->query('to');

        if ($preset === 'custom' && $from && $to) {
            $start = Carbon::parse($from)->startOfDay();
            $end = Carbon::parse($to)->endOfDay();
            return ['start' => $start, 'end' => $end, 'label' => $start->format('M j, Y') . ' - ' . $end->format('M j, Y')];
        }

        switch ($preset) {
            case 'today':
                $start = Carbon::today();
                $end = Carbon::today();
                $label = 'Today';
                break;
            case 'week':
                $start = Carbon::now()->startOfWeek();
                $end = Carbon::now()->endOfWeek();
                $label = 'This Week';
                break;
            case 'month':
                $start = Carbon::now()->startOfMonth();
                $end = Carbon::now()->endOfMonth();
                $label = 'This Month';
                break;
            case 'year':
                $start = Carbon::now()->startOfYear();
                $end = Carbon::now()->endOfYear();
                $label = 'This Year';
                break;
            case 'last_12_months':
            default:
                $start = Carbon::now()->subMonths(11)->startOfMonth();
                $end = Carbon::now()->endOfMonth();
                $label = 'Last 12 Months';
                break;
        }

        return ['start' => $start, 'end' => $end, 'label' => $label];
    }

    protected function buildPatientQuery(array $filters, ?Carbon $start = null, ?Carbon $end = null)
    {
        $query = Patient::query()
            ->leftJoin('users', 'users.id', '=', 'patients.user_id')
            ->select(['patients.*', 'users.is_active as patient_is_active']);

        if (! empty($filters['condition'])) {
            $query->where('patients.condition', $filters['condition']);
        }

        if (! empty($filters['therapist'])) {
            $query->where('patients.assigned_to', $filters['therapist']);
        }

        if (! empty($filters['status'])) {
            $query->where('users.is_active', $filters['status'] === 'active');
        }

        if ($start && $end) {
            $query->whereBetween('patients.created_at', [$start->startOfDay(), $end->endOfDay()]);
        }

        return $query;
    }

    protected function buildRegistrationTrend(array $filters, Carbon $start, Carbon $end): array
    {
        $labels = [];
        $values = [];

        $bucketType = $start->diffInDays($end) <= 31 ? 'day' : 'month';

        if ($bucketType === 'day') {
            $cursor = $start->copy()->startOfDay();
            while ($cursor->lte($end)) {
                $labels[] = $cursor->format('M d');
                $values[$cursor->format('Y-m-d')] = 0;
                $cursor->addDay();
            }

            $trendData = $this->buildPatientQuery($filters, $start, $end)
                ->select(DB::raw('DATE(patients.created_at) as bucket'), DB::raw('COUNT(*) as total'))
                ->groupBy('bucket')
                ->pluck('total', 'bucket')
                ->toArray();
        } else {
            $cursor = $start->copy()->startOfMonth();
            while ($cursor->lte($end->copy()->endOfMonth())) {
                $labels[] = $cursor->format('M Y');
                $values[$cursor->format('Y-m')] = 0;
                $cursor->addMonth();
            }

            $month = DB::connection()->getDriverName() === 'sqlite'
                ? "strftime('%Y-%m', patients.created_at)"
                : "DATE_FORMAT(patients.created_at, '%Y-%m')";

            $trendData = $this->buildPatientQuery($filters, $start, $end)
                ->select(DB::raw("{$month} as bucket"), DB::raw('COUNT(*) as total'))
                ->groupBy('bucket')
                ->pluck('total', 'bucket')
                ->toArray();
        }

        foreach ($values as $bucket => $count) {
            $values[$bucket] = (int) ($trendData[$bucket] ?? 0);
        }

        return [
            'labels' => array_values($labels),
            'values' => array_values($values),
        ];
    }

    protected function buildConditionChart($patients): array
    {
        $conditionCounts = [];

        foreach ($patients as $patient) {
            $condition = trim((string) ($patient->condition ?? '')) ?: 'Unspecified';
            $conditionCounts[$condition] = ($conditionCounts[$condition] ?? 0) + 1;
        }

        ksort($conditionCounts);

        return [
            'labels' => array_keys($conditionCounts),
            'values' => array_values($conditionCounts),
        ];
    }

    protected function buildGrowthComparison(array $filters, array $range): array
    {
        $currentPeriodPatients = $this->buildPatientQuery($filters, $range['start'], $range['end'])->count();

        $intervalDays = $range['start']->diffInDays($range['end']) + 1;
        $previousStart = $range['start']->copy()->subDays($intervalDays);
        $previousEnd = $range['end']->copy()->subDays($intervalDays);

        $previousPeriodPatients = $this->buildPatientQuery($filters, $previousStart, $previousEnd)->count();

        $result = [
            'currentPatients' => $currentPeriodPatients,
            'currentPeriodLabel' => $range['label'],
            'previousPeriodLabel' => $previousStart->format('M j, Y') . ' - ' . $previousEnd->format('M j, Y'),
        ];

        if ($previousPeriodPatients === 0 && $currentPeriodPatients === 0) {
            return $result + [
                'comparisonMessage' => 'No patient data is available for the selected comparison period.',
                'trendText' => 'No comparison data available',
            ];
        }

        if ($previousPeriodPatients === 0) {
            return $result + [
                'comparisonMessage' => 'No previous-period data available to compare.',
                'trendText' => 'New patient records detected in the current period.',
            ];
        }

        $changePercent = (($currentPeriodPatients - $previousPeriodPatients) / $previousPeriodPatients) * 100;

        return $result + [
            'comparisonMessage' => null,
            'trendText' => sprintf('%s%0.1f%%', $changePercent >= 0 ? '+' : '', $changePercent) . ' vs previous period',
        ];
    }
}
