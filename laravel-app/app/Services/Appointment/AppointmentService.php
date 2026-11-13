<?php

namespace App\Services\Appointment;

use App\Auth\StaffUser;
use App\Services\Clinic\ClinicRecord;
use App\Services\Clinic\ClinicStore;
use App\Services\Firebase\FirebaseTransport;
use App\Services\Patient\PatientService;
use App\Services\User\StaffDirectory;
use App\Services\User\UserService;
use Carbon\CarbonImmutable;
use Illuminate\Validation\ValidationException;

/** Clinic appointments (Firestore `appointments`, see ClinicStore). */
class AppointmentService
{
    public function __construct(
        private ClinicStore $store,
        private PatientService $patients,
        private UserService $users,
        private FirebaseTransport $firebase,
        private StaffDirectory $directory,
    ) {
    }

    public function overview(StaffUser $user): array
    {
        $today = now()->toDateString();

        [$appointments, $visiblePatients] = $this->firebase->concurrently([
            fn () => $this->store->all(ClinicStore::APPOINTMENTS),
            fn () => $this->patients->visible($user),
        ]);
        // A physical therapist sees their own appointments.
        if ($user->isTherapist()) {
            $appointments = $appointments->where('therapistId', $user->id);
        }

        $appointments = $appointments->sortBy(fn (ClinicRecord $a) => $a->date.' '.$a->time)
            ->map(fn (ClinicRecord $a) => $this->presented($a))
            ->values();

        return [
            'appointments' => $appointments,
            'todayAppointments' => $appointments->where('date', $today)->count(),
            'upcomingAppointments' => $appointments->where('status', 'Upcoming')->count(),
            'activePatients' => count($visiblePatients),
            'completedToday' => $appointments->filter(fn (ClinicRecord $a) => $a->status === 'Completed' && (
                $a->completed_at
                    ? CarbonImmutable::instance($a->completed_at)->setTimezone(config('app.timezone'))->toDateString() === $today
                    : $a->date === $today
            ))->count(),
        ];
    }

    /**
     * The upcoming appointments set for this therapist, soonest first. Shown in the
     * bell at the top of the dashboard.
     *
     * @return list<ClinicRecord>
     */
    public function upcomingFor(string $therapistId, int $limit = 10): array
    {
        $today = now()->toDateString();

        return $this->store->where(ClinicStore::APPOINTMENTS, 'therapistId', $therapistId)
            ->filter(fn (ClinicRecord $a) => $a->status === 'Upcoming' && $a->date >= $today)
            ->sortBy(fn (ClinicRecord $a) => $a->date.' '.$a->time)
            ->take($limit)
            ->values()
            ->all();
    }

    /** Active patients this user can see, for the patient name picker. */
    public function activePatients(StaffUser $user): array
    {
        return $this->patients->visible($user);
    }

    /** Active therapists from Firebase (appointments store the therapist's name). */
    public function therapists(): array
    {
        return $this->users->therapists();
    }

    public function find(string $id): ClinicRecord
    {
        return $this->presented($this->store->findOrFail(ClinicStore::APPOINTMENTS, $id));
    }

    public function create(array $data): string
    {
        $data = $this->withTherapist($data);
        $data['status'] = $data['status'] ?? 'Upcoming';
        $data['completed_at'] = $data['status'] === 'Completed' ? CarbonImmutable::now() : null;

        return $this->store->create(ClinicStore::APPOINTMENTS, $this->fields($data));
    }

    public function update(ClinicRecord $appointment, array $data): void
    {
        $data = $this->withTherapist($data);
        $data['status'] = $data['status'] ?? $appointment->status;
        $data['completed_at'] = $data['status'] === 'Completed'
            ? ($appointment->status === 'Completed' && $appointment->completed_at ? $appointment->completed_at : CarbonImmutable::now())
            : null;

        $this->store->update(ClinicStore::APPOINTMENTS, $appointment->id, $this->fields($data));
    }

    public function changeStatus(ClinicRecord $appointment, string $status): void
    {
        $this->store->update(ClinicStore::APPOINTMENTS, $appointment->id, [
            'status' => $status,
            'completed_at' => $status === 'Completed' ? CarbonImmutable::now() : null,
        ]);
    }

    public function delete(ClinicRecord $appointment): void
    {
        $this->store->delete(ClinicStore::APPOINTMENTS, $appointment->id);
    }

    /** The therapist picked on the form, checked against the active therapists. */
    private function withTherapist(array $data): array
    {
        $therapist = collect($this->users->therapists())->firstWhere('uid', $data['therapist_id']);

        if ($therapist === null) {
            throw ValidationException::withMessages(['therapist_id' => 'Choose an active therapist.']);
        }

        return array_merge($data, ['therapistId' => $therapist['uid'], 'therapist' => $therapist['name']]);
    }

    /** Shows the therapist's current name. The saved name is only a fallback. */
    private function presented(ClinicRecord $appointment): ClinicRecord
    {
        return new ClinicRecord(array_merge($appointment->toArray(), [
            'therapist' => $this->directory->name($appointment->therapistId, (string) $appointment->therapist),
        ]));
    }

    /** The stored shape: every form field, the date as Y-m-d text. */
    private function fields(array $data): array
    {
        return [
            'patient' => $data['patient'],
            'therapistId' => $data['therapistId'],
            'therapist' => $data['therapist'],
            'patient_condition' => $data['patient_condition'],
            'contact' => $data['contact'],
            'date' => CarbonImmutable::parse($data['date'])->toDateString(),
            'time' => (string) $data['time'],
            'session' => $data['session'],
            'notes' => $data['notes'] ?? null,
            'status' => $data['status'],
            'completed_at' => $data['completed_at'],
        ];
    }
}
