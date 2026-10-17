<?php

namespace App\Services\Dashboard;

use App\Auth\StaffUser;
use App\Services\Patient\PatientService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Collection;

/**
 * Patient registration statistics (admin only), computed from the Firestore
 * patients collection. "Active" means not archived (the app login is enabled).
 */
class PatientStatisticsService
{
    public function __construct(private PatientService $patients)
    {
    }

    public function patientStatistics(Request $request): array
    {
        $filters = $this->resolveFilters($request);
        $range = $this->resolveDateRange($request);
        $all = $this->allPatients($request->user());
        $selected = $this->filter($all, $filters, $range['start'], $range['end']);

        return [
            'filters' => $filters,
            'rangeLabel' => $range['label'],
            'summary' => $this->summary($all, $selected, $filters),
            'registrationTrend' => $this->buildRegistrationTrend($all, $filters, $range['start'], $range['end']),
            'conditionChart' => $this->buildConditionChart($selected),
            'growthSummary' => $this->buildGrowthComparison($all, $filters, $range),
            'recentPatients' => $this->paginate($selected, 10, $request),
            'conditionOptions' => $this->distinct($all, 'condition'),
            'therapistOptions' => $this->distinct($all, 'assigned_to'),
        ];
    }

    /**
     * Rows for the patient statistics CSV export.
     */
    public function patientStatisticsCsvRows(Request $request): array
    {
        $filters = $this->resolveFilters($request);
        $range = $this->resolveDateRange($request);
        $all = $this->allPatients($request->user());
        $selected = $this->filter($all, $filters, $range['start'], $range['end']);
        $summary = $this->summary($all, $selected, $filters);

        $rows = [
            ['RehabPlus', 'Patient Statistics'],
            ['Selected range', $range['label']],
            ['Generated', now()->format('F j, Y H:i:s')],
            [],
            ['Total Patients', $summary['totalPatients']],
            ['Active Patients', $summary['activePatients']],
            ['Inactive Patients', $summary['inactivePatients']],
            ['New Patients This Month', $summary['newPatientsThisMonth']],
            [],
            ['Patient Name', 'Condition', 'Assigned Therapist', 'Registration Date', 'Status'],
        ];

        foreach ($selected as $patient) {
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
        $all = $this->allPatients($request->user());
        $selected = $this->filter($all, $filters, $range['start'], $range['end']);

        return [
            'summary' => $this->summary($all, $selected, $filters),
            'rangeLabel' => $range['label'],
            'recentPatients' => $this->paginate($selected, 20, $request),
        ];
    }

    /** Patients (newest first) as objects with the properties the statistics views use. */
    protected function allPatients(StaffUser $user): Collection
    {
        return collect($this->patients->visible($user, includeArchived: true))
            ->map(fn (array $p) => (object) [
                'id' => $p['uid'],
                'name' => $p['name'],
                'condition' => $p['condition'],
                'assigned_to' => $p['therapistName'],
                'created_at' => $p['createdAt'] ? Carbon::instance($p['createdAt'])->setTimezone(config('app.timezone')) : null,
                'patient_is_active' => $p['archived'] ? 0 : 1,
            ])
            ->sortByDesc(fn ($p) => $p->created_at?->getTimestamp() ?? 0)
            ->values();
    }

    protected function summary(Collection $all, Collection $selected, array $filters): array
    {
        return [
            'totalPatients' => $selected->count(),
            'activePatients' => $selected->where('patient_is_active', 1)->count(),
            'inactivePatients' => $selected->where('patient_is_active', 0)->count(),
            'newPatientsThisMonth' => $this->filter($all, $filters, Carbon::now()->startOfMonth(), Carbon::now()->endOfMonth())->count(),
        ];
    }

    protected function filter(Collection $patients, array $filters, ?Carbon $start = null, ?Carbon $end = null): Collection
    {
        $from = $start?->copy()->startOfDay();
        $to = $end?->copy()->endOfDay();

        return $patients->filter(function ($p) use ($filters, $from, $to) {
            if ($filters['condition'] !== '' && $p->condition !== $filters['condition']) {
                return false;
            }
            if ($filters['therapist'] !== '' && $p->assigned_to !== $filters['therapist']) {
                return false;
            }
            if ($filters['status'] !== '' && (bool) $p->patient_is_active !== ($filters['status'] === 'active')) {
                return false;
            }

            return ! $from || ($p->created_at && $p->created_at->between($from, $to));
        })->values();
    }

    protected function paginate(Collection $items, int $perPage, Request $request): LengthAwarePaginator
    {
        $page = LengthAwarePaginator::resolveCurrentPage();

        return new LengthAwarePaginator(
            $items->forPage($page, $perPage)->values(),
            $items->count(),
            $perPage,
            $page,
            ['path' => $request->url(), 'query' => $request->query()],
        );
    }

    protected function distinct(Collection $patients, string $field): array
    {
        return $patients->pluck($field)->filter(fn ($v) => $v !== null && $v !== '')->unique()->sort()->values()->all();
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

            return ['start' => $start, 'end' => $end, 'label' => $start->format('M j, Y').' - '.$end->format('M j, Y')];
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

    protected function buildRegistrationTrend(Collection $all, array $filters, Carbon $start, Carbon $end): array
    {
        $byDay = $start->diffInDays($end) <= 31;
        $format = $byDay ? 'Y-m-d' : 'Y-m';
        $labels = [];
        $values = [];

        $cursor = $byDay ? $start->copy()->startOfDay() : $start->copy()->startOfMonth();
        $last = $byDay ? $end->copy() : $end->copy()->endOfMonth();
        while ($cursor->lte($last)) {
            $labels[] = $cursor->format($byDay ? 'M d' : 'M Y');
            $values[$cursor->format($format)] = 0;
            $byDay ? $cursor->addDay() : $cursor->addMonth();
        }

        foreach ($this->filter($all, $filters, $start, $end) as $patient) {
            $bucket = $patient->created_at->format($format);
            if (isset($values[$bucket])) {
                $values[$bucket]++;
            }
        }

        return [
            'labels' => $labels,
            'values' => array_values($values),
        ];
    }

    protected function buildConditionChart(Collection $patients): array
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

    protected function buildGrowthComparison(Collection $all, array $filters, array $range): array
    {
        $currentPeriodPatients = $this->filter($all, $filters, $range['start'], $range['end'])->count();

        $intervalDays = (int) $range['start']->diffInDays($range['end']) + 1;
        $previousStart = $range['start']->copy()->subDays($intervalDays);
        $previousEnd = $range['end']->copy()->subDays($intervalDays);

        $previousPeriodPatients = $this->filter($all, $filters, $previousStart, $previousEnd)->count();

        $result = [
            'currentPatients' => $currentPeriodPatients,
            'currentPeriodLabel' => $range['label'],
            'previousPeriodLabel' => $previousStart->format('M j, Y').' - '.$previousEnd->format('M j, Y'),
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
            'trendText' => sprintf('%s%0.1f%%', $changePercent >= 0 ? '+' : '', $changePercent).' vs previous period',
        ];
    }
}
