<?php

namespace App\Http\Controllers;

use App\Models\Appointment;
use App\Models\ExerciseRecord;
use App\Models\Patient;
use App\Services\Patient\PatientService;
use Illuminate\Support\Facades\Auth;

class PatientPortalController extends Controller
{
    public function index(PatientService $patients)
    {
        $patient = Patient::where('user_id', Auth::id())->first();

        if (! $patient) {
            return redirect()->route('login.page')->with('error', 'Patient profile not found.');
        }

        $records = ExerciseRecord::where('patient_id', $patient->id)->orderByDesc('recorded_at')->get();
        $appointments = Appointment::where('patient', $patient->name)->orderBy('date', 'asc')->orderBy('time', 'asc')->get();

        return view('patient_portal.index', compact('patient', 'records', 'appointments') + $patients->progress($records));
    }
}
