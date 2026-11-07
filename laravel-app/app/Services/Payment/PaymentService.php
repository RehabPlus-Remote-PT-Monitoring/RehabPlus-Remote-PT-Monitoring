<?php

namespace App\Services\Payment;

use App\Auth\StaffUser;
use App\Services\Clinic\ClinicRecord;
use App\Services\Clinic\ClinicStore;
use App\Services\Firebase\FirebaseTransport;
use Carbon\CarbonImmutable;
use Illuminate\Validation\ValidationException;

/** Billing and payment records (Firestore `payments`, see ClinicStore). */
class PaymentService
{
    public function __construct(
        private ClinicStore $store,
        private FirebaseTransport $firebase,
    ) {
    }

    public function overview(StaffUser $user): array
    {
        [$payments, $billablePatients] = $this->firebase->concurrently([
            fn () => $this->store->all(ClinicStore::PAYMENTS),
            fn () => $this->billablePatients($user),
        ]);
        $payments = $payments->sortByDesc(fn (ClinicRecord $p) => $p->date)->values();
        $fee = fn (ClinicRecord $p) => (float) $p->fee;

        return [
            'billablePatients' => $billablePatients,
            'sessionFees' => '₱'.number_format($payments->sum($fee), 2),
            'paymentStatus' => $payments->where('status', 'Paid')->count(),
            'outstanding' => '₱'.number_format($payments->whereIn('status', ['Pending', 'Partial'])->sum($fee), 2),
            'paymentHistory' => $payments->count(),
            'payments' => $payments->map(fn (ClinicRecord $p) => new ClinicRecord(
                ['fee' => number_format((float) $p->fee, 2, '.', '')] + $p->toArray(),
            )),
        ];
    }

    public function create(StaffUser $user, array $data): string
    {
        $patient = collect($this->billablePatients($user))->firstWhere('name', $data['patient']);

        if ($patient === null) {
            throw ValidationException::withMessages(['patient' => 'Choose a patient with an appointment.']);
        }
        if (! in_array($data['session'], $patient['sessions'], true)) {
            throw ValidationException::withMessages(['session' => "Choose one of this patient's sessions."]);
        }

        return $this->store->create(ClinicStore::PAYMENTS, [
            'patient' => $data['patient'],
            'session' => $data['session'],
            'fee' => round((float) $data['fee'], 2),
            'status' => $data['status'],
            'date' => CarbonImmutable::parse($data['date'])->toDateString(),
        ]);
    }

    /** A paid record's status is final, so a settled payment can't be quietly reopened. */
    public function updateStatus(string $id, string $status): void
    {
        if ($this->store->findOrFail(ClinicStore::PAYMENTS, $id)->status === 'Paid') {
            throw ValidationException::withMessages(['status' => "This payment is already paid, so its status can't be changed."]);
        }

        $this->store->update(ClinicStore::PAYMENTS, $id, ['status' => $status]);
    }

    public function delete(string $id): void
    {
        $this->store->findOrFail(ClinicStore::PAYMENTS, $id);
        $this->store->delete(ClinicStore::PAYMENTS, $id);
    }

    /**
     * The patients the billing form offers: everyone with an appointment, each
     * with their session types. Therapists only get their own appointments.
     * Appointments keep the patient as typed text, so names match ignoring case
     * and surrounding spaces.
     *
     * @return list<array{name: string, sessions: list<string>}>
     */
    private function billablePatients(StaffUser $user): array
    {
        $appointments = $user->isTherapist()
            ? $this->store->where(ClinicStore::APPOINTMENTS, 'therapistId', $user->id)
            : $this->store->all(ClinicStore::APPOINTMENTS);
        $key = fn (mixed $text) => mb_strtolower((string) $text);

        return $appointments
            ->map(fn (ClinicRecord $a) => ['name' => trim((string) $a->patient), 'session' => trim((string) $a->session)])
            ->filter(fn (array $a) => $a['name'] !== '' && $a['session'] !== '')
            ->sortBy('name')
            ->groupBy(fn (array $a) => $key($a['name']))
            ->map(fn ($rows) => [
                'name' => $rows->first()['name'],
                'sessions' => $rows->pluck('session')
                    ->sort()
                    ->unique($key)
                    ->sort(fn (string $a, string $b) => strnatcasecmp($a, $b))
                    ->values()
                    ->all(),
            ])
            ->sort(fn (array $a, array $b) => strnatcasecmp($a['name'], $b['name']))
            ->values()
            ->all();
    }
}
