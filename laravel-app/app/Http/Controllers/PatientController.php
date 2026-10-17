<?php

namespace App\Http\Controllers;

use App\Helpers\PatientValidation;
use App\Models\Patient;
use App\Services\Patient\PatientService;
use Illuminate\Http\Request;
use Illuminate\View\View;

class PatientController extends Controller
{
    public function __construct(private PatientService $patients)
    {
    }

    public function index(Request $request): View
    {
        return view('patients.index', $this->patients->search(
            trim((string) $request->query('search', '')),
            trim((string) $request->query('condition', ''))
        ));
    }

    public function show(int $id)
    {
        return view('patients.show', $this->patients->profile(Patient::findOrFail($id)));
    }

    public function create(): View
    {
        return view('patients.form', ['patient' => null, 'errors' => []]);
    }

    public function store(Request $request)
    {
        $this->patients->create(PatientValidation::patient($request), $request->file('avatar'));

        return redirect()->route('patients.index')->with('success', 'Patient added successfully.');
    }

    public function edit(int $id)
    {
        return view('patients.form', ['patient' => Patient::findOrFail($id), 'errors' => []]);
    }

    public function update(Request $request, int $id)
    {
        $patient = Patient::findOrFail($id);

        $this->patients->update($patient, PatientValidation::patient($request), $request->file('avatar'));

        return redirect()->route('patients.index')->with('success', 'Patient updated successfully.');
    }

    public function delete(int $id)
    {
        Patient::findOrFail($id)->delete();

        return redirect()->route('patients.index')->with('success', 'Patient deleted.');
    }
}
