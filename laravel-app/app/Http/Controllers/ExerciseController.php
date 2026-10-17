<?php

namespace App\Http\Controllers;

use App\Helpers\ExerciseValidation;
use App\Models\ExerciseRecord;
use App\Models\Patient;
use Illuminate\Http\Request;

class ExerciseController extends Controller
{
    public function create(int $patientId)
    {
        return view('exercises.form', [
            'record' => null,
            'patient' => Patient::findOrFail($patientId),
            'patientId' => $patientId,
        ]);
    }

    public function store(Request $request, int $patientId)
    {
        $validated = ExerciseValidation::record($request);
        $validated['patient_id'] = $patientId;
        ExerciseRecord::create($validated);

        return redirect()->route('patients.show', $patientId)->with('success', 'Record added.');
    }

    public function edit(int $patientId, int $id)
    {
        return view('exercises.form', [
            'record' => ExerciseRecord::findOrFail($id),
            'patient' => Patient::findOrFail($patientId),
            'patientId' => $patientId,
        ]);
    }

    public function update(Request $request, int $patientId, int $id)
    {
        $record = ExerciseRecord::findOrFail($id);

        $record->update(ExerciseValidation::record($request));

        return redirect()->route('patients.show', $patientId)->with('success', 'Record updated.');
    }

    public function delete(int $patientId, int $id)
    {
        ExerciseRecord::findOrFail($id)->delete();

        return redirect()->route('patients.show', $patientId)->with('success', 'Record deleted.');
    }
}
