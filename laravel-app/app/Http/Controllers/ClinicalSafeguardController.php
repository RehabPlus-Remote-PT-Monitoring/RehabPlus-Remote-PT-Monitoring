<?php

namespace App\Http\Controllers;

use App\Helpers\ClinicalSafeguardValidation;
use App\Services\Patient\ClearanceGate;
use App\Services\Patient\ClearanceService;
use App\Services\Patient\ClinicalProfileService;
use App\Services\Patient\ExerciseCatalog;
use App\Services\Patient\PatientService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;
use Illuminate\View\View;

/**
 * Clinical safeguards on a patient (API_CONTRACT.md "Clinical safeguards"):
 * the clinician-validated clinical & dietary profile and the physician
 * clearance sign-off. Both are shown on the patient page; this controller
 * handles the edits.
 *
 * The service account bypasses Firestore rules, so the scoping is here:
 * admins, or the therapist the patient is assigned to. Anyone else gets a
 * 404, as for other clinical records (front desk staff are stopped earlier
 * by the role:admin,therapist route middleware).
 */
class ClinicalSafeguardController extends Controller
{
    public function __construct(
        private PatientService $patients,
        private ClinicalProfileService $profiles,
        private ClearanceService $clearances,
    ) {
    }

    public function editProfile(Request $request, string $uid): View
    {
        $patient = $this->patient($request, $uid);

        return view('patients.clinical-profile', [
            'patient' => $patient,
            'profile' => $this->profiles->read($uid),
            'catalog' => ExerciseCatalog::TYPES,
            'nutritionFlags' => ClinicalProfileService::NUTRITION_FLAGS,
            'reassessmentDates' => ClinicalSafeguardValidation::reassessmentDates(),
        ]);
    }

    public function updateProfile(Request $request, string $uid): RedirectResponse
    {
        $patient = $this->patient($request, $uid);
        $this->profiles->save($request->user(), $patient, ClinicalSafeguardValidation::profile($request));

        return redirect()->to(route('patients.show', $uid).'#clinical-profile')
            ->with('success', 'Clinical profile saved. The app uses the new restrictions the next time it loads the plan.');
    }

    /**
     * Record a physician's decision. `cleared` is checked against the
     * completion gate recomputed here from fresh reads, so no form value
     * (or an out-of-date page) can clear a patient whose program isn't
     * complete. `not_cleared` is always allowed (reassessment).
     */
    public function storeClearance(Request $request, string $uid): RedirectResponse
    {
        $patient = $this->patient($request, $uid);
        $data = ClinicalSafeguardValidation::clearance($request);
        $gate = $this->clearances->currentGate($uid);

        if ($data['decision'] === ClearanceService::CLEARED && $gate['state'] !== ClearanceGate::READY_FOR_REVIEW) {
            Log::info('clearances.cleared_refused', ['patient' => $uid, 'state' => $gate['state'], 'missing' => count($gate['missing'])]);

            $missing = $gate['state'] === ClearanceGate::NO_PROGRAM
                ? 'the patient has no active exercises'
                : implode('; ', array_map(fn ($r) => ClearanceGate::describe($r), $gate['missing']));

            throw ValidationException::withMessages([
                'decision' => "Medical clearance can't be recorded yet because the exercise program isn't complete: {$missing}. You can still record \"Not cleared\".",
            ])->redirectTo(route('patients.show', $uid).'#clearance');
        }

        $this->clearances->record($request->user(), $patient, $data, $gate);

        return redirect()->to(route('patients.show', $uid).'#clearance')->with(
            'success',
            $data['decision'] === ClearanceService::CLEARED
                ? 'Medical clearance recorded. The patient was notified in the app.'
                : 'Decision recorded: not cleared. The program continues.',
        );
    }

    /** A patient this user may change: admin, or their own therapist. Others 404. */
    private function patient(Request $request, string $uid): array
    {
        $patient = $this->patients->find($request->user(), $uid);
        abort_unless($patient && $this->patients->canManage($request->user(), $patient), 404);

        return $patient;
    }
}
