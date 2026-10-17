<?php

namespace App\Http\Controllers;

use App\Helpers\AppointmentValidation;
use App\Models\Appointment;
use App\Services\Appointment\AppointmentService;
use Illuminate\Http\Request;
use Illuminate\View\View;

class AppointmentController extends Controller
{
    public function __construct(private AppointmentService $appointments)
    {
    }

    public function index(): View
    {
        return view('appointments.index', $this->appointments->overview());
    }

    public function create(): View
    {
        return view('appointments.create', [
            'appointment' => null,
            'therapists' => $this->appointments->therapists(),
            'errors' => [],
        ]);
    }

    public function show(int $id)
    {
        return view('appointments.show', ['appointment' => Appointment::findOrFail($id)]);
    }

    public function store(Request $request)
    {
        $this->appointments->create(AppointmentValidation::appointment($request));

        return redirect()->route('appointments.index')->with('success', 'Appointment scheduled successfully.');
    }

    public function edit(int $id)
    {
        return view('appointments.create', [
            'appointment' => Appointment::findOrFail($id),
            'therapists' => $this->appointments->therapists(),
            'errors' => [],
        ]);
    }

    public function update(Request $request, int $id)
    {
        $appointment = Appointment::findOrFail($id);

        $this->appointments->update($appointment, AppointmentValidation::appointment($request));

        return redirect()->route('appointments.index')->with('success', 'Appointment updated successfully.');
    }

    public function delete(int $id)
    {
        Appointment::findOrFail($id)->delete();

        return redirect()->route('appointments.index')->with('success', 'Appointment deleted successfully.');
    }

    public function changeStatus(Request $request, int $id)
    {
        $appointment = Appointment::findOrFail($id);
        $status = $request->input('status');

        if (! AppointmentValidation::isValidStatus($status)) {
            return redirect()->route('appointments.index')->with('error', 'Invalid appointment status.');
        }

        $this->appointments->changeStatus($appointment, $status);

        return redirect()->route('appointments.index')->with('success', 'Appointment status updated.');
    }
}
