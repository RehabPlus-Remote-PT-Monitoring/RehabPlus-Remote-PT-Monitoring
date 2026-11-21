<?php

namespace App\Http\Controllers;

use App\Helpers\PrescriptionValidation;
use App\Services\Patient\ClinicalProfileService;
use App\Services\Patient\ExerciseCatalog;
use App\Services\Patient\PatientService;
use App\Services\Patient\PrescriptionService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;
use Illuminate\View\View;

/** Assigning exercises to a patient (patients/{uid}/prescriptions). */
class PrescriptionController extends Controller
{
    public function __construct(
        private PatientService $patients,
        private PrescriptionService $prescriptions,
        private ClinicalProfileService $profiles,
    ) {
    }

    public function create(Request $request, string $uid): View
    {
        return view('prescriptions.form', [
            'patient' => $this->patient($request, $uid),
            'prescription' => null,
            'catalog' => ExerciseCatalog::TYPES,
            'intensityProfile' => $this->intensityProfile($uid),
        ]);
    }

    public function store(Request $request, string $uid): RedirectResponse
    {
        $patient = $this->patient($request, $uid);
        $data = PrescriptionValidation::prescription($request);
        $this->refuseRestricted($uid, $data['exercise_type'], 'exercise_type');

        $this->prescriptions->create($request->user(), $patient, $data);

        return redirect()->route('patients.show', $uid)->with('success', 'Exercise assigned. It now shows in the patient\'s app.');
    }

    public function edit(Request $request, string $uid, string $id): View
    {
        $patient = $this->patient($request, $uid);

        return view('prescriptions.form', [
            'patient' => $patient,
            'prescription' => $this->prescription($uid, $id),
            'catalog' => ExerciseCatalog::TYPES,
            'intensityProfile' => $this->intensityProfile($uid),
        ]);
    }

    public function update(Request $request, string $uid, string $id): RedirectResponse
    {
        $patient = $this->patient($request, $uid);
        $prescription = $this->prescription($uid, $id);
        $data = PrescriptionValidation::prescription($request);
        $this->refuseRestricted($uid, $data['exercise_type'], 'exercise_type');

        $this->prescriptions->update($patient, $prescription, $data);

        return redirect()->route('patients.show', $uid)->with('success', 'Exercise updated.');
    }

    /** Stop (active=false) or resume an exercise. Resuming a restricted one is refused. */
    public function toggle(Request $request, string $uid, string $id): RedirectResponse
    {
        $patient = $this->patient($request, $uid);
        $prescription = $this->prescription($uid, $id);
        $active = $request->boolean('active');

        if ($active) {
            $message = $this->restrictionMessage($uid, $prescription['exerciseType']);
            if ($message !== null) {
                return redirect()->route('patients.show', $uid)->withErrors(['active' => $message]);
            }
        }

        $this->prescriptions->setActive($patient, $prescription, $active);

        return redirect()->route('patients.show', $uid)->with('success', $active ? 'Exercise resumed.' : 'Exercise stopped. It no longer shows in the app; past sessions are kept.');
    }

    /**
     * A validation error when the clinician restricted this exercise for the
     * patient (clinical profile). The profile read throws on a Firebase
     * failure, so an unreadable restriction list never lets a restricted
     * exercise through: the request fails with the friendly Firebase error.
     */
    private function refuseRestricted(string $uid, string $exerciseType, string $field): void
    {
        $message = $this->restrictionMessage($uid, $exerciseType);
        if ($message !== null) {
            throw ValidationException::withMessages([$field => $message]);
        }
    }

    private function restrictionMessage(string $uid, string $exerciseType): ?string
    {
        if (! in_array($exerciseType, $this->profiles->read($uid)['restrictedExercises'], true)) {
            return null;
        }

        Log::info('prescriptions.restricted_refused', ['patient' => $uid, 'exercise' => $exerciseType]);

        return ExerciseCatalog::name($exerciseType).' is restricted by the clinician in this patient\'s clinical profile, so it can\'t be assigned or resumed. Change the clinical profile first if that is no longer the case.';
    }

    /**
     * The clinical profile when the patient is marked low tolerance (the form
     * then shows "review the exercise intensity"), else null. Uses the
     * never-throwing page read: a failed read only hides the reminder, the
     * restriction checks on save still use the strict read.
     */
    private function intensityProfile(string $uid): ?array
    {
        $result = $this->profiles->forPatient($uid);

        return $result['status'] === ClinicalProfileService::OK && $result['profile']['lowTolerance'] ? $result['profile'] : null;
    }

    private function patient(Request $request, string $uid): array
    {
        $patient = $this->patients->find($request->user(), $uid);
        abort_unless($patient, 404);
        abort_unless($this->patients->canManage($request->user(), $patient), 403);

        return $patient;
    }

    private function prescription(string $uid, string $id): array
    {
        $prescription = $this->prescriptions->find($uid, $id);
        abort_unless($prescription, 404);

        return $prescription;
    }
}
