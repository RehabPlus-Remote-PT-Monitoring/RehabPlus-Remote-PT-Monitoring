<?php

namespace App\Services\Appointment;

use App\Auth\StaffUser;
use App\Models\Appointment;
use App\Services\Patient\PatientService;
use App\Services\User\UserService;

class AppointmentService
{
    public function __construct(private PatientService $patients, private UserService $users)
    {
    }

    public function overview(StaffUser $user): array
    {
        $today = now()->toDateString();

        return [
            'appointments' => Appointment::orderBy('date', 'asc')->orderBy('time', 'asc')->get(),
            'todayAppointments' => Appointment::where('date', $today)->count(),
            'upcomingAppointments' => Appointment::where('status', 'Upcoming')->count(),
            'activePatients' => count($this->patients->visible($user)),
            'completedToday' => Appointment::where('status', 'Completed')
                ->where(function ($query) use ($today) {
                    $query->whereNotNull('completed_at')->whereDate('completed_at', $today)
                        ->orWhere(function ($q) use ($today) {
                            $q->whereNull('completed_at')->whereDate('date', $today);
                        });
                })
                ->count(),
        ];
    }

    /** Active therapists from Firebase (appointments store the therapist's name). */
    public function therapists(): array
    {
        return $this->users->therapists();
    }

    public function create(array $data): Appointment
    {
        $data['status'] = $data['status'] ?? 'Upcoming';
        $data['completed_at'] = $data['status'] === 'Completed' ? now() : null;

        return Appointment::create($data);
    }

    public function update(Appointment $appointment, array $data): void
    {
        $data['status'] = $data['status'] ?? $appointment->status;
        $data['completed_at'] = $data['status'] === 'Completed'
            ? ($appointment->status === 'Completed' && ! empty($appointment->completed_at) ? $appointment->completed_at : now())
            : null;

        $appointment->update($data);
    }

    public function changeStatus(Appointment $appointment, string $status): void
    {
        $appointment->update([
            'status' => $status,
            'completed_at' => $status === 'Completed' ? now() : null,
        ]);
    }
}
