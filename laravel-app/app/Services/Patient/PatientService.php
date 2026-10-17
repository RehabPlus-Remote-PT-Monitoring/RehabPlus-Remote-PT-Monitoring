<?php

namespace App\Services\Patient;

use App\Models\ExerciseRecord;
use App\Models\Patient;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Storage;

class PatientService
{
    public function search(string $search, string $condition): array
    {
        $query = Patient::query()->orderBy('name', 'asc');

        if ($search !== '') {
            $query->where(function ($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                  ->orWhere('condition', 'like', "%{$search}%");
            });
        }

        if ($condition !== '') {
            $query->where('condition', $condition);
        }

        return [
            'data' => $query->get(),
            'conditions' => Patient::query()->select('condition')->distinct()->orderBy('condition', 'asc')->pluck('condition'),
            'search' => $search,
            'selectedCondition' => $condition,
        ];
    }

    public function profile(Patient $patient): array
    {
        $records = ExerciseRecord::where('patient_id', $patient->id)->orderByDesc('recorded_at')->get();

        $trend = ExerciseRecord::where('patient_id', $patient->id)
            ->selectRaw('DATE(recorded_at) as day, ROUND(AVG(pain_level), 1) as avg_pain, ROUND(SUM(sets_completed) / NULLIF(SUM(sets_prescribed), 0) * 100, 1) as compliance_rate')
            ->groupBy('day')
            ->orderBy('day', 'desc')
            ->limit(14)
            ->get()
            ->toArray();

        return [
            'patient' => $patient,
            'records' => $records,
            'trend' => array_reverse($trend),
        ] + $this->progress($records);
    }

    /**
     * Compliance % and average pain for a patient's exercise records.
     */
    public function progress(Collection $records): array
    {
        $prescribed = $records->sum('sets_prescribed');
        $completed = $records->sum('sets_completed');

        return [
            'compliance' => $prescribed ? round(($completed / $prescribed) * 100, 1) : 0,
            'avgPain' => $records->count() ? round($records->avg('pain_level'), 1) : 0,
        ];
    }

    public function create(array $data, ?UploadedFile $avatar): Patient
    {
        if ($avatar) {
            $data['avatar'] = $avatar->store('avatars', 'public');
        }

        return Patient::create($data);
    }

    public function update(Patient $patient, array $data, ?UploadedFile $avatar): void
    {
        if ($avatar) {
            if ($patient->avatar && Storage::disk('public')->exists($patient->avatar)) {
                Storage::disk('public')->delete($patient->avatar);
            }

            $data['avatar'] = $avatar->store('avatars', 'public');
        }

        $patient->update($data);
    }
}
