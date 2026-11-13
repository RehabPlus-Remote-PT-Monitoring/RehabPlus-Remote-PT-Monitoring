<?php

namespace App\Http\Controllers;

use App\Helpers\AppointmentValidation;
use App\Services\Appointment\AppointmentService;
use App\Services\Notice\StaffNoticeService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

class AppointmentController extends Controller
{
    public function __construct(private AppointmentService $appointments, private StaffNoticeService $notices)
    {
    }

    /** Administrators see every appointment; a physical therapist sees their own. */
    public function index(Request $request): View
    {
        return view('appointments.index', $this->appointments->overview($request->user()));
    }

    public function create(Request $request): View
    {
        return view('appointments.create', [
            'appointment' => null,
            'therapists' => $this->appointments->therapists(),
            'patients' => $this->appointments->activePatients($request->user()),
        ]);
    }

    public function show(Request $request, string $id)
    {
        $appointment = $this->appointments->find($id);
        abort_unless($request->user()->isAdmin() || $appointment->therapistId === $request->user()->id, 404);

        return view('appointments.show', ['appointment' => $appointment, 'canRequest' => ! $request->user()->isAdmin()]);
    }

    public function store(Request $request)
    {
        $data = AppointmentValidation::appointment($request);
        $id = $this->appointments->create($data);

        $this->tellTherapist($request, $data['therapist_id'], 'New appointment scheduled', ['id' => $id] + $data);

        return redirect()->route('appointments.index')->with('success', 'Appointment scheduled successfully.');
    }

    public function edit(Request $request, string $id)
    {
        return view('appointments.create', [
            'appointment' => $this->appointments->find($id),
            'therapists' => $this->appointments->therapists(),
            'patients' => $this->appointments->activePatients($request->user()),
        ]);
    }

    public function update(Request $request, string $id)
    {
        $appointment = $this->appointments->find($id);
        $data = AppointmentValidation::appointment($request);

        $this->appointments->update($appointment, $data);

        $this->tellTherapist($request, $data['therapist_id'], 'Appointment updated', ['id' => $appointment->id] + $data);
        if ($appointment->therapistId !== $data['therapist_id']) {
            $this->tellTherapist($request, $appointment->therapistId, 'Appointment reassigned to another therapist', ['id' => $appointment->id] + $appointment->toArray());
        }

        return redirect()->route('appointments.index')->with('success', 'Appointment updated successfully.');
    }

    public function delete(string $id)
    {
        $this->appointments->delete($this->appointments->find($id));

        return redirect()->route('appointments.index')->with('success', 'Appointment deleted successfully.');
    }

    public function changeStatus(Request $request, string $id)
    {
        $appointment = $this->appointments->find($id);
        $status = $request->input('status');

        if (! AppointmentValidation::isValidStatus($status)) {
            return redirect()->route('appointments.index')->with('error', 'Invalid appointment status.');
        }

        $this->appointments->changeStatus($appointment, $status);

        if (in_array($status, ['Cancelled', 'Completed'], true)) {
            $this->tellTherapist($request, $appointment->therapistId, 'Appointment '.strtolower($status), array_merge($appointment->toArray(), ['id' => $appointment->id, 'status' => $status]));
        }

        return redirect()->route('appointments.index')->with('success', 'Appointment status updated.');
    }

    /**
     * A physical therapist asks the clinic to change one of their appointments. Every
     * administrator is told, with the appointment's details and the reason.
     */
    public function requestChange(Request $request, string $id): RedirectResponse
    {
        $appointment = $this->appointments->find($id);
        abort_unless($request->user()->isAdmin() || $appointment->therapistId === $request->user()->id, 404);

        $data = $request->validate(['message' => ['required', 'string', 'min:5', 'max:500']]);

        $this->notices->sendToAdmins(
            StaffNoticeService::TYPE_REQUEST,
            'Schedule change requested',
            implode("\n", array_filter([
                'Patient: '.$appointment->patient,
                'Date and time: '.$this->dateLine($appointment->date, $appointment->time),
                'Requested by: '.$request->user()->name,
                'Reason: '.$data['message'],
            ])),
            $appointment->id,
            $request->user()->name,
        );

        return redirect()->route('appointments.show', $appointment->id)->with('success', 'Your request was sent to the administrators.');
    }

    /** Tells a physical therapist about one of their appointments: the details, in the bell. */
    private function tellTherapist(Request $request, ?string $therapistUid, string $title, array $appointment): void
    {
        if ($therapistUid === null || $therapistUid === '') {
            return; // no physical therapist is assigned, so there is nobody to tell
        }

        $this->notices->send(
            $therapistUid,
            StaffNoticeService::TYPE_APPOINTMENT,
            $title,
            $this->summary($appointment),
            $appointment['id'] ?? null,
            $request->user()->name,
        );
    }

    /** The details a therapist needs at a glance, one per line. */
    private function summary(array $appointment): string
    {
        return implode("\n", array_filter([
            'Patient: '.($appointment['patient'] ?? ''),
            'Session: '.($appointment['session'] ?? ''),
            'Date and time: '.$this->dateLine($appointment['date'] ?? '', $appointment['time'] ?? ''),
            ! empty($appointment['contact']) ? 'Contact: '.$appointment['contact'] : null,
            ! empty($appointment['patient_condition'] ?? $appointment['condition'] ?? null)
                ? 'Condition: '.($appointment['patient_condition'] ?? $appointment['condition'])
                : null,
            'Status: '.($appointment['status'] ?? 'Upcoming'),
        ]));
    }

    private function dateLine(string $date, string $time): string
    {
        $day = rescue(fn () => \Carbon\CarbonImmutable::parse($date)->format('D, M j, Y'), $date, false);

        return trim($day.' at '.$time, ' at');
    }
}
