@extends('layouts.admin')

@section('title', $appointment ? 'Edit Appointment' : 'Schedule Appointment')

@section('content')
    @php($status = old('status', $appointment->status ?? 'Upcoming'))
    @php($contact = \App\Helpers\PhoneNumber::parse($appointment->contact ?? ''))
    @php($contactCountry = old('contact_country', $contact['iso']))
    @php($contactNumber = old('contact', $contact['national']))
    <div class="mb-3">
        <a href="{{ route('appointments.index') }}" class="back-link text-decoration-none small">
            <i class="bi bi-arrow-left me-1"></i>Back to appointments
        </a>
        <p class="page-title mb-1 mt-1">{{ $appointment ? 'Edit Appointment' : 'Schedule Appointment' }}</p>
    </div>

    @include('partials.flash')

    <form method="POST" action="{{ $appointment ? route('appointments.update', $appointment->id) : route('appointments.store') }}" class="card shadow-sm border-0" style="max-width: 900px;">
        @csrf
        @if ($appointment)
            @method('PUT')
        @endif

        <div class="card-body p-4">
            <div class="row g-3">
                <div class="col-md-6">
                    <label for="patient" class="form-label small fw-semibold">Patient name</label>
                    <div class="position-relative" data-patient-picker>
                        <div class="input-group">
                            <input id="patient" type="text" name="patient" data-patient-name class="form-control @error('patient') is-invalid @enderror" value="{{ old('patient', $appointment->patient ?? '') }}" required maxlength="100" autocomplete="off">
                            <button type="button" class="btn btn-outline-secondary" data-patient-toggle aria-label="Choose from active patients" aria-expanded="false" @disabled(empty($patients))>
                                <i class="bi bi-chevron-down"></i>
                            </button>
                        </div>
                        @error('patient')
                            <div class="invalid-feedback d-block">{{ $message }}</div>
                        @enderror
                        <div class="dropdown-menu w-100 p-0 overflow-hidden" data-patient-menu>
                            @if (empty($patients))
                                <div class="px-3 py-2 small text-muted">No active patients yet. Type the name instead.</div>
                            @else
                                <div class="p-2 border-bottom">
                                    <input type="search" class="form-control form-control-sm" placeholder="Search patients" aria-label="Search patients" data-patient-search>
                                </div>
                                <div class="overflow-auto" style="max-height: 240px;">
                                    @foreach ($patients as $p)
                                        <button type="button" class="dropdown-item py-2" data-patient-option data-name="{{ $p['name'] }}" data-search="{{ $p['name'].' '.$p['condition'] }}">
                                            <span class="d-block">{{ $p['name'] }}</span>
                                            @if ($p['condition'] !== '')
                                                <span class="d-block small text-muted">{{ $p['condition'] }}</span>
                                            @endif
                                        </button>
                                    @endforeach
                                </div>
                                <div class="px-3 py-2 small text-muted" data-patient-empty hidden>No patient matches. The typed name will be used.</div>
                            @endif
                        </div>
                    </div>
                </div>
                <div class="col-md-6">
                    <label for="therapist" class="form-label small fw-semibold">Therapist</label>
                    <select id="therapist" name="therapist_id" class="form-select @error('therapist_id') is-invalid @enderror" required>
                        <option value="">Select therapist</option>
                        @foreach ($therapists as $therapist)
                            <option value="{{ $therapist['uid'] }}" @selected(old('therapist_id', $appointment->therapistId ?? '') === $therapist['uid'])>{{ $therapist['name'] }}</option>
                        @endforeach
                    </select>
                    @error('therapist_id')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>

                <div class="col-md-6">
                    <label for="patient_condition" class="form-label small fw-semibold">Condition</label>
                    <input id="patient_condition" type="text" name="patient_condition" class="form-control @error('patient_condition') is-invalid @enderror" value="{{ old('patient_condition', $appointment->patient_condition ?? '') }}" required maxlength="150" placeholder="e.g. MCL sprain, post-acute">
                    @error('patient_condition')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                @include('partials.phone-field', ['field' => 'contact', 'label' => 'Contact', 'country' => $contactCountry, 'number' => $contactNumber, 'initial' => null, 'required' => true])

                <div class="col-md-6">
                    <label for="date" class="form-label small fw-semibold">Date</label>
                    @php($appointmentDates = \App\Helpers\AppointmentValidation::dates())
                    <div class="input-group">
                        <input id="date" type="date" name="date" class="form-control @error('date') is-invalid @enderror" value="{{ old('date', $appointment->date ?? '') }}" min="{{ $appointmentDates['min'] }}" max="{{ $appointmentDates['max'] }}" data-calendar-only required>
                        <button type="button" class="btn btn-primary field-picker-button" data-date-open aria-label="Open calendar" title="Open calendar"><i class="bi bi-calendar3" aria-hidden="true"></i></button>
                    </div>
                    @error('date')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="col-md-6">
                    <label for="time" class="form-label small fw-semibold">Time</label>
                    <div class="input-group">
                        <input id="time" type="text" name="time" class="form-control @error('time') is-invalid @enderror" list="time-options" value="{{ old('time', $appointment->time ?? '') }}" placeholder="e.g. 9:30 AM" autocomplete="off" required>
                        <button type="button" class="btn btn-primary field-picker-button" data-list-open aria-label="Show times" title="Show times"><i class="bi bi-clock" aria-hidden="true"></i></button>
                        <datalist id="time-options">
                            @foreach (\App\Helpers\AppointmentValidation::timeOptions() as $option)
                                <option value="{{ $option }}">
                            @endforeach
                        </datalist>
                    </div>
                    @error('time')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>

                <div class="col-md-6">
                    <label for="session" class="form-label small fw-semibold">Session</label>
                    <div class="input-group">
                        <input id="session" type="text" name="session" class="form-control @error('session') is-invalid @enderror" list="session-options" value="{{ old('session', $appointment->session ?? '') }}" placeholder="Choose or type a session" autocomplete="off" required maxlength="100">
                        <button type="button" class="btn btn-primary field-picker-button" data-list-open aria-label="Show sessions" title="Show sessions"><i class="bi bi-chevron-down" aria-hidden="true"></i></button>
                        <datalist id="session-options">
                            @foreach (\App\Helpers\AppointmentValidation::sessionOptions() as $option)
                                <option value="{{ $option }}">
                            @endforeach
                        </datalist>
                    </div>
                    @error('session')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="col-md-6">
                    <label for="status" class="form-label small fw-semibold">Status</label>
                    <div class="input-group">
                    <select id="status" name="status" class="form-select status-select">
                        <option value="Upcoming" @selected($status === 'Upcoming')>Upcoming</option>
                        <option value="Completed" @selected($status === 'Completed')>Completed</option>
                        {{-- A new appointment can't already be cancelled; cancelling is done when editing it. --}}
                        @if ($appointment)
                            <option value="Cancelled" @selected($status === 'Cancelled')>Cancelled</option>
                        @endif
                    </select>
                        <button type="button" class="btn btn-primary field-picker-button" data-select-open aria-label="Show statuses" title="Show statuses"><i class="bi bi-chevron-down" aria-hidden="true"></i></button>
                    </div>
                </div>

                <div class="col-12">
                    <label for="notes" class="form-label small fw-semibold">Notes</label>
                    <textarea id="notes" name="notes" class="form-control" rows="3" maxlength="2000">{{ old('notes', $appointment->notes ?? '') }}</textarea>
                </div>
            </div>
        </div>
        <div class="card-footer bg-transparent text-end">
            <button type="submit" class="btn btn-primary px-4">{{ $appointment ? 'Update Appointment' : 'Create Appointment' }}</button>
        </div>
    </form>
@endsection
