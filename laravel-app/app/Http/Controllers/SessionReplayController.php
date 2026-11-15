<?php

namespace App\Http\Controllers;

use App\Services\Patient\PatientService;
use App\Services\Patient\ReplayService;
use Illuminate\Http\Request;
use Illuminate\View\View;

/**
 * The movement replay page: a session's saved pose points played back as a
 * stick figure (no video exists). Admins and the patient's own therapist
 * only; the route sits in the role:admin,therapist group and the patient is
 * looked up with the same scoping as the patient page, so another
 * therapist's patient is a 404, not a hint that it exists.
 */
class SessionReplayController extends Controller
{
    public function __construct(
        private PatientService $patients,
        private ReplayService $replays,
    ) {}

    public function show(Request $request, string $uid, string $sessionId): View
    {
        $patient = $this->patients->find($request->user(), $uid);
        abort_unless($patient, 404);

        $found = $this->replays->forSession($uid, $sessionId);
        abort_unless($found, 404);

        return view('patients.replay', [
            'patient' => $patient,
            'session' => $found['session'],
            'replay' => $found['replay'],
        ]);
    }
}
