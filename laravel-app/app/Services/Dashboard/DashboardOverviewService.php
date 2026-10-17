<?php

namespace App\Services\Dashboard;

use App\Models\ExerciseRecord;
use App\Models\Patient;

class DashboardOverviewService
{
    /**
     * Stat cards, recovery chart and condition chart data for the dashboard and analytics pages.
     */
    public function overview(): array
    {
        $patientStats = ExerciseRecord::patientStats();
        $recentRecords = ExerciseRecord::recentRecords(10);
        $totalPatients = Patient::count();

        $patientsWithRecords = array_values(array_filter($patientStats, fn (array $patient): bool => (int) $patient['total_sessions'] > 0));
        $recordedPatientCount = count($patientsWithRecords);
        $avgCompliance = $recordedPatientCount ? round(array_sum(array_column($patientsWithRecords, 'compliance_rate')) / $recordedPatientCount, 1) : 0;
        $avgPain = $recordedPatientCount ? round(array_sum(array_column($patientsWithRecords, 'avg_pain')) / $recordedPatientCount, 1) : 0;
        $hasRecoveryData = $recordedPatientCount > 0;

        $recoveryLabels = array_column($patientStats, 'name');
        $recoveryValues = array_map(fn (array $patient): float => (float) ($patient['recovery_score'] ?? 0), $patientStats);

        $conditionCounts = [];
        foreach ($patientStats as $patient) {
            $condition = $patient['condition'];
            $conditionCounts[$condition] = ($conditionCounts[$condition] ?? 0) + 1;
        }

        return compact(
            'patientStats',
            'recentRecords',
            'totalPatients',
            'avgCompliance',
            'avgPain',
            'hasRecoveryData',
            'recoveryLabels',
            'recoveryValues',
            'conditionCounts'
        );
    }
}
